import Combine
import Foundation

@MainActor
final class CleanupSuggestionsViewModel: ObservableObject {
    @Published var scope: AnalysisScope = .month
    @Published private(set) var suggestions: [CleanupSuggestion] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0

    // nil이면 모든 이유
    @Published var reasonFilter: CleanupReason?

    // 휴지통으로 보낼 사진. 추천된 사진은 처음부터 선택돼 있고, 탭해서 뺄 수 있다.
    @Published private var selectedIDs: Set<String> = []

    // 이번에 휴지통으로 옮긴 사진 수
    @Published private(set) var trashedCount = 0

    // 마지막으로 휴지통에 넣은 사진과 원래 위치 (실행 취소용)
    @Published private var lastTrashed: [(index: Int, suggestion: CleanupSuggestion)] = []
    var canUndo: Bool { !lastTrashed.isEmpty }
    var lastTrashedCount: Int { lastTrashed.count }

    private let store: ReviewStateStore
    private var analysisTask: Task<Void, Never>?
    private var generation = 0

    init(store: ReviewStateStore = ReviewStateStore()) {
        self.store = store
    }

    // MARK: - 보이는 목록
    var visibleSuggestions: [CleanupSuggestion] {
        guard let reasonFilter else { return suggestions }
        return suggestions.filter { $0.reasons.contains(reasonFilter) }
    }

    func count(for reason: CleanupReason) -> Int {
        suggestions.filter { $0.reasons.contains(reason) }.count
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

        let stream = CleanupSuggestionAnalyzer.analyze(since: scope.since, excluding: store.trashedIDs)
        analysisTask = Task { [weak self] in
            for await event in stream {
                guard let self, current == self.generation else { return }
                switch event {
                case .progress(let done, let total):
                    self.analyzedCount = done
                    self.totalCount = total
                case .suggestion(let suggestion):
                    self.suggestions.append(suggestion)
                    self.selectedIDs.insert(suggestion.id)
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

    func clearUndo() {
        lastTrashed = []
    }
}
