import Combine
import Foundation
import SwiftUI

// 분석할 기간 (비슷한 사진, 정리 추천 공통)
enum AnalysisScope: String, CaseIterable, Identifiable {
    case month, year, all

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .month: return "최근 1개월"
        case .year: return "최근 1년"
        case .all: return "전체"
        }
    }

    var since: Date? {
        let cal = Calendar.current
        switch self {
        case .month: return cal.date(byAdding: .month, value: -1, to: Date())
        case .year: return cal.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}

@MainActor
final class SimilarPhotosViewModel: ObservableObject {
    @Published var period: CleanupPeriod = .scope(.month)
    // '직접 선택' 기간 (양 끝 날짜 포함)
    @Published var customStart = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @Published var customEnd = Date()
    // 종류·상태·정렬. 기간을 바꿔도 유지한다.
    @Published var filter = CleanupFilter()
    @Published private(set) var groups: [SimilarGroup] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0

    // 묶음 ID → 남길 사진 ID. 처음에는 추천 사진만 남긴다.
    @Published private var keepIDs: [String: Set<String>] = [:]

    // 이번에 휴지통으로 옮긴 사진 수
    @Published private(set) var trashedCount = 0

    // 마지막으로 정리한 묶음들 (실행 취소용)
    private struct CleanedGroup {
        let group: SimilarGroup
        let index: Int
        let kept: Set<String>
        let trashed: Set<String>
    }
    @Published private var lastCleaned: [CleanedGroup] = []
    var canUndo: Bool { !lastCleaned.isEmpty }
    var lastTrashedCount: Int { lastCleaned.reduce(0) { $0 + $1.trashed.count } }

    // 지금 보이는 묶음에서 남기지 않은 사진 수
    var totalTrashCount: Int { visibleGroups.reduce(0) { $0 + trashCount(in: $1) } }

    // 앨범·셀카 소속 (분석을 시작할 때 다시 모은다)
    @Published private var membership = PhotoMembership()

    private let store: ReviewStateStore
    private var analysisTask: Task<Void, Never>?
    private var membershipTask: Task<Void, Never>?
    private var generation = 0

    init(store: ReviewStateStore = ReviewStateStore()) {
        self.store = store
    }

    // MARK: - 보이는 목록
    // 조건에 맞는 사진이 한 장이라도 있는 묶음
    var visibleGroups: [SimilarGroup] {
        var list = groups
        if filter.activeCount > 0 {
            let seenIDs = store.seenIDs
            list = list.filter { group in
                filter.matchesAny(group.items.map { item in
                    var facts = membership.facts(for: item.asset, seenIDs: seenIDs)
                    facts.categories = group.categories[item.id] ?? []
                    return facts
                })
            }
        }
        if filter.sort == .largest { list.sort { $0.bytes > $1.bytes } }
        return list
    }

    // 묶음이 없을 때 넓혀 볼 다음 기간. 이미 전체면 nil.
    var widerPeriod: CleanupPeriod? { period.wider }

    // MARK: - 분석
    func start() {
        analysisTask?.cancel()
        generation += 1
        let current = generation

        groups = []
        keepIDs = [:]
        lastCleaned = []
        analyzedCount = 0
        totalCount = 0
        isAnalyzing = true

        membershipTask?.cancel()
        membershipTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { PhotoMembership.load() }.value
            guard let self, current == self.generation else { return }
            self.membership = loaded
        }

        let range = period.dateRange(customStart: customStart, customEnd: customEnd)
        let stream = SimilarPhotoAnalyzer.analyze(since: range.since, until: range.until,
                                                  excluding: store.trashedIDs)
        analysisTask = Task { [weak self] in
            for await event in stream {
                guard let self, current == self.generation else { return }
                switch event {
                case .progress(let done, let total):
                    self.analyzedCount = done
                    self.totalCount = total
                case .group(let group):
                    self.groups.append(group)
                    self.keepIDs[group.id] = [group.bestID]
                }
            }
            guard let self, current == self.generation else { return }
            self.isAnalyzing = false
        }
    }

    func stop() {
        analysisTask?.cancel()
        analysisTask = nil
        membershipTask?.cancel()
        membershipTask = nil
        generation += 1
        isAnalyzing = false
    }

    // MARK: - 선택
    func isKept(_ photoID: String, in group: SimilarGroup) -> Bool {
        keepIDs[group.id]?.contains(photoID) ?? false
    }

    func toggleKeep(_ photoID: String, in group: SimilarGroup) {
        var kept = keepIDs[group.id] ?? []
        if kept.contains(photoID) {
            kept.remove(photoID)
        } else {
            kept.insert(photoID)
        }
        keepIDs[group.id] = kept
    }

    func trashCount(in group: SimilarGroup) -> Int {
        group.items.count - (keepIDs[group.id]?.count ?? 0)
    }

    // MARK: - 정리
    // 남기지 않은 사진을 앱 휴지통으로 옮긴다 (실제 삭제는 휴지통을 비울 때).
    func cleanUp(_ group: SimilarGroup) {
        guard let cleaned = trash(group) else { return }
        lastCleaned = [cleaned]
    }

    // 남기기로 한 사진까지 묶음 전체를 휴지통으로 옮긴다.
    func trashEntire(_ group: SimilarGroup) {
        guard let cleaned = trash(group, keepingSelection: false) else { return }
        lastCleaned = [cleaned]
    }

    // 보이는 묶음을 한 번에 정리한다. 남길 사진만 있는 묶음은 그대로 둔다.
    func cleanUpAll() {
        lastCleaned = visibleGroups
            .filter { trashCount(in: $0) > 0 }
            .compactMap { trash($0) }
    }

    private func trash(_ group: SimilarGroup, keepingSelection: Bool = true) -> CleanedGroup? {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return nil }
        let kept = keepIDs[group.id] ?? []
        let trashed = Set(group.items.map(\.id)).subtracting(keepingSelection ? kept : [])

        store.addAllToTrash(trashed)
        store.markAllSeen(Set(group.items.map(\.id)))
        trashedCount += trashed.count

        groups.remove(at: index)
        keepIDs[group.id] = nil
        return CleanedGroup(group: group, index: index, kept: kept, trashed: trashed)
    }

    // 이번에는 정리하지 않고 목록에서만 뺀다.
    func skip(_ group: SimilarGroup) {
        groups.removeAll { $0.id == group.id }
        keepIDs[group.id] = nil
    }

    func undo() {
        // 정리한 역순으로 되돌려야 원래 위치에 들어간다.
        for cleaned in lastCleaned.reversed() {
            store.removeFromTrash(cleaned.trashed)
            trashedCount -= cleaned.trashed.count
            groups.insert(cleaned.group, at: min(cleaned.index, groups.count))
            keepIDs[cleaned.group.id] = cleaned.kept
        }
        lastCleaned = []
    }

    func clearUndo() {
        lastCleaned = []
    }
}
