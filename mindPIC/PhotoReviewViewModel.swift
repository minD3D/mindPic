import Combine
import Photos
import UIKit

@MainActor
final class PhotoReviewViewModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false

    @Published private(set) var filterType: PhotoFilterType = .random100

    // 안 본 사진만 보기 토글
    @Published var onlyUnseen: Bool = false

    // ✅ 랜덤100 다 봤을 때 팝업 띄우기 트리거
    @Published var shouldAskForNewRandom: Bool = false

    // 마지막으로 휴지통에 넣은 사진 (실행 취소용)
    @Published private var lastDeleted: (item: PhotoItem, index: Int)?
    var canUndoDelete: Bool { lastDeleted != nil }

    // 본 사진 / 휴지통 ID 저장
    private let store: ReviewStateStore

    var trashedPhotoIDs: Set<String> { store.trashedIDs }

    // 필터를 빠르게 연속 변경할 때, 늦게 끝난 이전 조회 결과가 덮어쓰지 않도록 하는 토큰
    private var loadGeneration = 0

    // 현재 프리히팅 중인 asset 목록 (변경분만 캐시 시작/중지하기 위함)
    private var cachedAssets: [PHAsset] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f
    }()

    init(store: ReviewStateStore = ReviewStateStore()) {
        self.store = store
    }

    var currentPhoto: PhotoItem? {
        guard currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var currentDateString: String? {
        guard let date = currentPhoto?.asset.creationDate else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    // MARK: - 필터 선택
    func selectRandom100() { load(.random100) }
    func selectYearsAgo(yearsBack: Int) { load(.yearsAgo(yearsBack)) }
    func selectMonthRange(from start: Date) { load(.monthRange(start)) }
    func selectRecent(days: Int) { load(.recentDays(days)) }
    func selectPeoplePortrait() { load(.peoplePortrait) }
    func selectNonFavorite() { load(.nonFavorite) }
    func selectScreenshot() { load(.screenshot) }
    func selectBurst() { load(.burst) }
    func selectTrash() { load(.trash) }

    // 현재 선택된 필터 다시 적용
    func reloadByFilter() { load(filterType) }

    // 🔹 랜덤 1개월 (전체 기간)
    // 라이브러리에서 사진 한 장을 무작위로 골라 그 사진이 속한 달을 보여준다.
    // 빈 달을 반복해서 찍어보던 재시도 없이 항상 사진이 있는 달이 선택된다.
    func selectRandomMonthFromLibrary() {
        let generation = beginLoading()
        Task {
            let monthStart = await Task.detached(priority: .userInitiated) {
                PhotoReviewViewModel.randomPhotoMonthStart()
            }.value
            guard generation == loadGeneration else { return }
            if let monthStart {
                load(.monthRange(monthStart))
            } else {
                finishLoading(with: [])
            }
        }
    }

    // MARK: - 로딩 공통
    private func beginLoading() -> Int {
        isLoading = true
        loadGeneration += 1
        return loadGeneration
    }

    // 사진 조회는 라이브러리 전체를 훑을 수 있어 메인 스레드 밖에서 수행한다.
    private func load(_ filter: PhotoFilterType) {
        filterType = filter
        let generation = beginLoading()

        let trashed = store.trashedIDs
        let seen = onlyUnseen ? store.seenIDs : []
        let isIncluded: @Sendable (String) -> Bool = filter == .trash
            ? { trashed.contains($0) }
            : { !trashed.contains($0) && !seen.contains($0) }

        Task {
            let items = await Task.detached(priority: .userInitiated) {
                PhotoReviewViewModel.fetchItems(for: filter, trashedIDs: trashed, isIncluded: isIncluded)
            }.value
            guard generation == loadGeneration else { return }

            if filter == .trash {
                // 라이브러리에서 이미 사라진 사진은 휴지통 목록에서도 정리
                let missing = trashed.subtracting(items.map(\.id))
                if !missing.isEmpty { updateTrash { $0.removeFromTrash(missing) } }
            }
            finishLoading(with: items)
        }
    }

    private func finishLoading(with items: [PhotoItem]) {
        photos = items
        currentIndex = 0
        isLoading = false
        shouldAskForNewRandom = false
        lastDeleted = nil
        updateCaching()
    }

    private func updateTrash(_ change: (ReviewStateStore) -> Void) {
        objectWillChange.send()
        change(store)
    }

    // MARK: - 사진 조회 (백그라운드)
    nonisolated private static func fetchItems(
        for filter: PhotoFilterType,
        trashedIDs: Set<String>,
        isIncluded: (String) -> Bool
    ) -> [PhotoItem] {
        let cal = Calendar.current
        let now = Date()

        switch filter {
        case .random100:
            // 전체를 PhotoItem으로 만든 뒤 섞지 않고, 필요한 100장만 무작위로 꺼낸다.
            let result = PHAsset.fetchAssets(with: .image, options: nil)
            return randomIndices(count: result.count, limit: 100) {
                isIncluded(result.object(at: $0).localIdentifier)
            }
            .map { PhotoItem(asset: result.object(at: $0)) }

        case .yearsAgo(let yearsBack):
            // N년 전 오늘 (±15일)
            let dayRange = 15
            guard let center = cal.date(byAdding: .year, value: -yearsBack, to: now),
                  let start = cal.date(byAdding: .day, value: -dayRange, to: center),
                  let end = cal.date(byAdding: .day, value: dayRange, to: center)
            else { return [] }
            return fetchImages(
                predicate: NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                       start as NSDate, end as NSDate),
                isIncluded: isIncluded)

        case .monthRange(let start):
            guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
            // 다음 달 1일 0시는 포함하지 않도록 end는 미만(<) 비교
            return fetchImages(
                predicate: NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                       start as NSDate, end as NSDate),
                isIncluded: isIncluded)

        case .recentDays(let days):
            guard let start = cal.date(byAdding: .day, value: -days, to: now) else { return [] }
            return fetchImages(predicate: NSPredicate(format: "creationDate >= %@", start as NSDate),
                               isIncluded: isIncluded)

        case .peoplePortrait:
            // 사람(Portrait, Depth Effect)
            return fetchImages(
                predicate: NSPredicate(format: "(mediaSubtype & %d) != 0",
                                       PHAssetMediaSubtype.photoDepthEffect.rawValue),
                isIncluded: isIncluded)

        case .nonFavorite:
            return fetchImages(predicate: NSPredicate(format: "isFavorite == NO"), isIncluded: isIncluded)

        case .screenshot:
            return fetchImages(
                predicate: NSPredicate(format: "(mediaSubtype & %d) != 0",
                                       PHAssetMediaSubtype.photoScreenshot.rawValue),
                isIncluded: isIncluded)

        case .burst:
            return fetchImages(isIncluded: isIncluded) { $0.representsBurst || $0.burstIdentifier != nil }

        case .trash:
            guard !trashedIDs.isEmpty else { return [] }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(trashedIDs),
                                             options: newestFirstOptions())
            var items: [PhotoItem] = []
            result.enumerateObjects { asset, _, _ in items.append(PhotoItem(asset: asset)) }
            return items
        }
    }

    nonisolated private static func newestFirstOptions(predicate: NSPredicate? = nil) -> PHFetchOptions {
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.predicate = predicate
        return opt
    }

    nonisolated private static func fetchImages(
        predicate: NSPredicate? = nil,
        isIncluded: (String) -> Bool,
        where matches: (PHAsset) -> Bool = { _ in true }
    ) -> [PhotoItem] {
        let result = PHAsset.fetchAssets(with: .image, options: newestFirstOptions(predicate: predicate))
        var items: [PhotoItem] = []
        for index in 0..<result.count {
            let asset = result.object(at: index)
            if matches(asset) && isIncluded(asset.localIdentifier) {
                items.append(PhotoItem(asset: asset))
            }
        }
        return items
    }

    nonisolated private static func randomPhotoMonthStart() -> Date? {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        guard result.count > 0,
              let date = result.object(at: Int.random(in: 0..<result.count)).creationDate
        else { return nil }
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date))
    }

    /// 0..<count 를 무작위 순서로 훑으며 조건을 만족하는 인덱스를 최대 limit개 고른다.
    nonisolated static func randomIndices(count: Int, limit: Int, where isIncluded: (Int) -> Bool) -> [Int] {
        var picked: [Int] = []
        picked.reserveCapacity(min(count, limit))
        for index in (0..<count).shuffled() {
            guard picked.count < limit else { break }
            if isIncluded(index) { picked.append(index) }
        }
        return picked
    }

    // MARK: - 이동 기능
    private func advance(by step: Int) {
        guard !photos.isEmpty else { return }

        // ✅ 랜덤100에서 마지막 사진인데 "다음" 시도하면 팝업 요청
        if step > 0, filterType == .random100, currentIndex >= photos.count - 1 {
            shouldAskForNewRandom = true
            return
        }

        let newIndex = min(max(currentIndex + step, 0), photos.count - 1)
        if newIndex != currentIndex {
            currentIndex = newIndex
            updateCaching()
        }
    }

    func next() { advance(by: 1) }
    func previous() { advance(by: -1) }
    func next5() { advance(by: 5) }

    func keep() {
        markCurrentAsSeen()
        next()
    }

    func like() {
        guard let asset = currentPhoto?.asset else { return }
        markCurrentAsSeen()
        next()
        Task {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = true
            }
        }
    }

    func delete() {
        guard let current = currentPhoto else { return }
        markCurrentAsSeen()
        updateTrash { $0.addToTrash(current.id) }

        let removeIndex = currentIndex
        lastDeleted = (current, removeIndex)
        photos.remove(at: removeIndex)
        if photos.isEmpty {
            currentIndex = 0
            if filterType == .random100 { shouldAskForNewRandom = true }
        } else if removeIndex >= photos.count {
            currentIndex = photos.count - 1
        }
        updateCaching()
    }

    // 방금 휴지통에 넣은 사진을 원래 자리로 되돌린다.
    func undoDelete() {
        guard let deleted = lastDeleted else { return }
        lastDeleted = nil
        updateTrash { $0.removeFromTrash([deleted.item.id]) }

        let insertIndex = min(deleted.index, photos.count)
        photos.insert(deleted.item, at: insertIndex)
        currentIndex = insertIndex
        shouldAskForNewRandom = false
        updateCaching()
    }

    private func markCurrentAsSeen() {
        if let id = currentPhoto?.id { store.markSeen(id) }
    }

    func emptyTrash() {
        let ids = store.trashedIDs
        guard !ids.isEmpty else { return }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }

        Task {
            if !assets.isEmpty {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets(assets as NSArray)
                    }
                } catch {
                    // 사용자가 시스템 삭제 확인을 취소한 경우 등: 휴지통 유지
                    return
                }
            }
            updateTrash { $0.removeFromTrash(ids) }
            if filterType == .trash { finishLoading(with: []) }
        }
    }

    func restore(photoID: String) {
        guard store.trashedIDs.contains(photoID) else { return }
        updateTrash { $0.removeFromTrash([photoID]) }

        if filterType == .trash, let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos.remove(at: index)
            if photos.isEmpty {
                currentIndex = 0
            } else if currentIndex >= photos.count {
                currentIndex = photos.count - 1
            }
        }
    }

    // MARK: - 이미지 캐싱
    // 현재 위치 기준 앞 5장 / 뒤 10장을 프리히팅하고, 바뀐 부분만 캐시를 갱신한다.
    private func updateCaching() {
        let window: [PHAsset]
        if photos.isEmpty {
            window = []
        } else {
            let range = max(0, currentIndex - 5)...min(photos.count - 1, currentIndex + 10)
            window = range.map { photos[$0].asset }
        }

        let newIDs = Set(window.map(\.localIdentifier))
        let oldIDs = Set(cachedAssets.map(\.localIdentifier))
        let removed = cachedAssets.filter { !newIDs.contains($0.localIdentifier) }
        let added = window.filter { !oldIDs.contains($0.localIdentifier) }

        if !removed.isEmpty {
            sharedImageManager.stopCachingImages(for: removed,
                                                 targetSize: ReviewImageSpec.targetSize,
                                                 contentMode: ReviewImageSpec.contentMode,
                                                 options: ReviewImageSpec.makeOptions())
        }
        if !added.isEmpty {
            sharedImageManager.startCachingImages(for: added,
                                                  targetSize: ReviewImageSpec.targetSize,
                                                  contentMode: ReviewImageSpec.contentMode,
                                                  options: ReviewImageSpec.makeOptions())
        }
        cachedAssets = window
    }

    func stopCaching() {
        sharedImageManager.stopCachingImagesForAllAssets()
        cachedAssets = []
    }
}
