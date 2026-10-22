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
    @Published var scope: AnalysisScope = .year
    @Published private(set) var groups: [SimilarGroup] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0

    // 묶음 ID → 남길 사진 ID. 처음에는 추천 사진만 남긴다.
    @Published private var keepIDs: [String: Set<String>] = [:]

    // 이번에 휴지통으로 옮긴 사진 수
    @Published private(set) var trashedCount = 0

    // 마지막으로 정리한 묶음 (실행 취소용)
    private struct CleanedGroup {
        let group: SimilarGroup
        let index: Int
        let kept: Set<String>
        let trashed: Set<String>
    }
    @Published private var lastCleaned: CleanedGroup?
    var canUndo: Bool { lastCleaned != nil }
    var lastTrashedCount: Int { lastCleaned?.trashed.count ?? 0 }

    private let store: ReviewStateStore
    private var analysisTask: Task<Void, Never>?
    private var generation = 0

    init(store: ReviewStateStore = ReviewStateStore()) {
        self.store = store
    }

    // MARK: - 분석
    func start() {
        analysisTask?.cancel()
        generation += 1
        let current = generation

        groups = []
        keepIDs = [:]
        lastCleaned = nil
        analyzedCount = 0
        totalCount = 0
        isAnalyzing = true

        let stream = SimilarPhotoAnalyzer.analyze(since: scope.since, excluding: store.trashedIDs)
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
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let kept = keepIDs[group.id] ?? []
        let trashed = Set(group.items.map(\.id)).subtracting(kept)

        store.addAllToTrash(trashed)
        store.markAllSeen(Set(group.items.map(\.id)))
        trashedCount += trashed.count

        lastCleaned = CleanedGroup(group: group, index: index, kept: kept, trashed: trashed)
        groups.remove(at: index)
        keepIDs[group.id] = nil
    }

    // 이번에는 정리하지 않고 목록에서만 뺀다.
    func skip(_ group: SimilarGroup) {
        groups.removeAll { $0.id == group.id }
        keepIDs[group.id] = nil
    }

    func undo() {
        guard let cleaned = lastCleaned else { return }
        lastCleaned = nil
        store.removeFromTrash(cleaned.trashed)
        trashedCount -= cleaned.trashed.count
        groups.insert(cleaned.group, at: min(cleaned.index, groups.count))
        keepIDs[cleaned.group.id] = cleaned.kept
    }

    func clearUndo() {
        lastCleaned = nil
    }
}
