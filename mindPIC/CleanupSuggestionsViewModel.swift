import Combine
import Foundation

@MainActor
final class CleanupSuggestionsViewModel: ObservableObject {
    @Published var period: CleanupPeriod = .scope(.month)
    // '직접 선택' 기간 (양 끝 날짜 포함)
    @Published var customStart = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @Published var customEnd = Date()
    // 종류·상태·정렬. 기간을 바꿔도 유지한다.
    @Published var filter = CleanupFilter()
    @Published private(set) var suggestions: [CleanupSuggestion] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0

    // nil이면 모든 이유
    @Published var reasonFilter: CleanupReason?

    // 휴지통으로 보낼 사진. 오탐이 있을 수 있어 처음엔 아무것도 고르지 않고, 사용자가 탭하거나 '모두 선택'으로 고른다.
    @Published private var selectedIDs: Set<String> = []

    // 이번에 휴지통으로 옮긴 사진 수
    @Published private(set) var trashedCount = 0

    // 마지막으로 휴지통에 넣은 사진과 원래 위치 (실행 취소용)
    @Published private var lastTrashed: [(index: Int, suggestion: CleanupSuggestion)] = []
    var canUndo: Bool { !lastTrashed.isEmpty }
    var lastTrashedCount: Int { lastTrashed.count }

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
    // 종류·상태 필터를 적용한 목록 (이유 칩 숫자의 기준)
    var filteredSuggestions: [CleanupSuggestion] {
        guard filter.activeCount > 0 else { return suggestions }
        let seenIDs = store.seenIDs
        return suggestions.filter { filter.matches(membership.facts(for: $0.item.asset, seenIDs: seenIDs)) }
    }

    var visibleSuggestions: [CleanupSuggestion] {
        var list = filteredSuggestions
        if let reasonFilter { list = list.filter { $0.reasons.contains(reasonFilter) } }
        if filter.sort == .largest { list.sort { $0.bytes > $1.bytes } }
        return list
    }

    func count(for reason: CleanupReason) -> Int {
        filteredSuggestions.filter { $0.reasons.contains(reason) }.count
    }

    var selectedVisibleBytes: Int64 {
        visibleSuggestions.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    private var dateRange: (since: Date?, until: Date?) {
        period.dateRange(customStart: customStart, customEnd: customEnd)
    }

    // 지금 목록에 나온 이유만 필터 칩으로 보여준다.
    var availableReasons: [CleanupReason] {
        CleanupReason.allCases.filter { count(for: $0) > 0 }
    }

    var selectedVisibleCount: Int {
        visibleSuggestions.filter { selectedIDs.contains($0.id) }.count
    }

    var allVisibleSelected: Bool {
        !visibleSuggestions.isEmpty && selectedVisibleCount == visibleSuggestions.count
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    // 추천이 없을 때 넓혀 볼 다음 기간. 이미 전체면 nil.
    var widerPeriod: CleanupPeriod? { period.wider }

    // MARK: - 분석
    func start() {
        analysisTask?.cancel()
        generation += 1
        let current = generation

        suggestions = []
        selectedIDs = []
        lastTrashed = []
        reasonFilter = nil
        analyzedCount = 0
        totalCount = 0
        isAnalyzing = true

        membershipTask?.cancel()
        membershipTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { PhotoMembership.load() }.value
            guard let self, current == self.generation else { return }
            self.membership = loaded
        }

        let range = dateRange
        let stream = CleanupSuggestionAnalyzer.analyze(since: range.since, until: range.until,
                                                       excluding: store.trashedIDs)
        analysisTask = Task { [weak self] in
            for await event in stream {
                guard let self, current == self.generation else { return }
                switch event {
                case .progress(let done, let total):
                    self.analyzedCount = done
                    self.totalCount = total
                case .suggestion(let suggestion):
                    self.suggestions.append(suggestion)
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
    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setAllVisible(selected: Bool) {
        let ids = Set(visibleSuggestions.map(\.id))
        if selected {
            selectedIDs.formUnion(ids)
        } else {
            selectedIDs.subtract(ids)
        }
    }

    // MARK: - 정리
    // 지금 보이는 목록에서 선택한 사진을 앱 휴지통으로 옮긴다 (실제 삭제는 휴지통을 비울 때).
    func trashSelected() {
        let visibleIDs = Set(visibleSuggestions.map(\.id))
        let moving = suggestions.enumerated().filter {
            visibleIDs.contains($0.element.id) && selectedIDs.contains($0.element.id)
        }
        guard !moving.isEmpty else { return }

        let ids = Set(moving.map { $0.element.id })
        store.addAllToTrash(ids)
        store.markAllSeen(ids)
        trashedCount += ids.count

        lastTrashed = moving.map { (index: $0.offset, suggestion: $0.element) }
        suggestions.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        if let reasonFilter, count(for: reasonFilter) == 0 { self.reasonFilter = nil }
    }

    func undo() {
        guard !lastTrashed.isEmpty else { return }
        let restoring = lastTrashed
        lastTrashed = []

        let ids = Set(restoring.map { $0.suggestion.id })
        store.removeFromTrash(ids)
        trashedCount -= ids.count

        // 앞 위치부터 다시 넣으면 원래 순서가 된다.
        for entry in restoring.sorted(by: { $0.index < $1.index }) {
            suggestions.insert(entry.suggestion, at: min(entry.index, suggestions.count))
        }
        selectedIDs.formUnion(ids)
    }

    // 사진 탐색에서 돌아왔을 때: 거기서 휴지통에 넣은 사진을 목록에서 빼고, 본 사진 기록을 갱신한다.
    func refreshFromStore() {
        store.reload()
        let trashed = store.trashedIDs
        guard suggestions.contains(where: { trashed.contains($0.id) }) else { return }
        suggestions.removeAll { trashed.contains($0.id) }
        selectedIDs.subtract(trashed)
        lastTrashed = []
        if let reasonFilter, count(for: reasonFilter) == 0 { self.reasonFilter = nil }
    }

    // 지금 보이는 목록을 사진 탐색 화면에서 한 장씩 넘겨 볼 수 있게 넘긴다.
    var exploreFilter: PhotoFilterType {
        .list(title: reasonFilter?.name ?? String(localized: "정리 추천"), ids: visibleSuggestions.map(\.id))
    }

    func clearUndo() {
        lastTrashed = []
    }
}
