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

    // 기기에 있는 사진만 보기 토글 (iCloud에서 받아야 하는 사진은 건너뜀). 앱을 다시 열어도 유지한다.
    @Published var onlyLocal: Bool = UserDefaults.standard.bool(forKey: PhotoReviewViewModel.onlyLocalKey) {
        didSet { UserDefaults.standard.set(onlyLocal, forKey: Self.onlyLocalKey) }
    }
    private static let onlyLocalKey = "onlyLocalPhotos"

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

    // 사진 ID → 기기에 리뷰 화질로 바로 보여줄 수 있는지 (false면 iCloud에서 받아야 함)
    private var localStatus: [String: Bool] = [:]
    private var availabilityTask: Task<Void, Never>?

    // 랜덤 100장에서 iCloud 사진을 기기에 있는 사진으로 바꿔 넣을 때 쓰는 여분 후보
    private var randomReserve: [PhotoItem] = []
    nonisolated private static let randomPoolSize = 300
    private static let randomCount = 100

    // 기기 확인은 앞으로 볼 사진 중 이 개수 안에서만 한다 (수천 장 필터에서 계속 돌지 않도록).
    private static let availabilityLookahead = 40

    // iCloud에만 있는 사진은 차례가 오기 전에 미리 받아 둔다.
    // 셀룰러·저데이터 모드에서는 데이터를, 저전력 모드에서는 배터리를 아끼려고 받지 않는다.
    private var cloudDownloadAhead: Int {
        if NetworkMonitor.shared.isExpensiveOrConstrained || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return 0
        }
        return 10
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(store: ReviewStateStore = ReviewStateStore()) {
        self.store = store
    }

    var currentPhoto: PhotoItem? {
        guard currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    // 카드 뒤에 미리 그려 둘 다음 사진
    var nextPhoto: PhotoItem? {
        let index = currentIndex + 1
        guard index < photos.count else { return nil }
        return photos[index]
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
        let seen: Set<String> = onlyUnseen ? store.seenIDs : []
        let isIncluded: @Sendable (String) -> Bool
        if filter == .trash {
            isIncluded = { trashed.contains($0) }
        } else {
            isIncluded = { !trashed.contains($0) && !seen.contains($0) }
        }
        
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

            var shown = items
            var reserve: [PhotoItem] = []
            if filter == .random100 {
                shown = Array(items.prefix(Self.randomCount))
                reserve = Array(items.dropFirst(Self.randomCount))
            }

            // 화면을 열자마자 흐린 사진이 보이지 않게, 첫 장은 기기에 있는 사진으로 맞춘다.
            var status: [String: Bool] = [:]
            if filter != .trash {
                (shown, reserve, status) = await prepareFirstPhoto(shown, reserve: reserve)
                guard generation == loadGeneration else { return }
            }
            finishLoading(with: shown, reserve: reserve, status: status)
        }
    }

    // 첫 장이 iCloud에만 있으면:
    // - '기기에 있는 사진만' 모드: 기기에 있는 사진이 나올 때까지 앞쪽 iCloud 사진을 뺀다.
    // - 그 외: 앞쪽 몇 장 중 기기에 있는 사진을 맨 앞으로 옮기고, 없으면 랜덤 여분에서 가져온다.
    private func prepareFirstPhoto(
        _ items: [PhotoItem], reserve: [PhotoItem]
    ) async -> ([PhotoItem], [PhotoItem], [String: Bool]) {
        let targetSize = ReviewImageSpec.targetSize
        var items = items
        var reserve = reserve
        var status: [String: Bool] = [:]

        func check(_ item: PhotoItem) async -> Bool {
            if LocalAvailabilityCache.knownLocal.contains(item.id) { return true }
            let isLocal = await Self.isLocallyAvailable(item.asset, targetSize: targetSize)
            status[item.id] = isLocal
            if isLocal { LocalAvailabilityCache.knownLocal.insert(item.id) }
            return isLocal
        }

        if onlyLocal {
            while let first = items.first, !(await check(first)) {
                items.removeFirst()
            }
            return (items, reserve, status)
        }

        for index in items.indices.prefix(8) {
            guard await check(items[index]) else { continue }
            if index > 0 { items.insert(items.remove(at: index), at: 0) }
            return (items, reserve, status)
        }
        for _ in 0..<3 where !reserve.isEmpty && !items.isEmpty {
            let candidate = reserve.removeFirst()
            if await check(candidate) {
                items.insert(candidate, at: 0)
                items.removeLast()   // 랜덤 100장 개수 유지
                break
            }
        }
        return (items, reserve, status)
    }

    private func finishLoading(with items: [PhotoItem], reserve: [PhotoItem] = [], status: [String: Bool] = [:]) {
        randomReserve = reserve
        photos = items
        currentIndex = 0
        isLoading = false
        shouldAskForNewRandom = false
        lastDeleted = nil
        localStatus = status
        for item in items where LocalAvailabilityCache.knownLocal.contains(item.id) {
            localStatus[item.id] = true
        }
        updateCaching()
        checkAvailability()
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
            // 전체를 PhotoItem으로 만든 뒤 섞지 않고, 필요한 만큼만 무작위로 꺼낸다.
            // 앞 100장을 보여주고 나머지는 iCloud 사진을 대신할 여분으로 쓴다.
            let result = PHAsset.fetchAssets(with: .image, options: nil)
            return randomIndices(count: result.count, limit: randomPoolSize) {
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
            if availabilityTask == nil { checkAvailability() }
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
        if availabilityTask == nil { checkAvailability() }
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

    // MARK: - 기기에 있는 사진 먼저 보여주기
    // 앞으로 볼 사진이 기기에 있는지 하나씩 확인하고, 있는 사진을 앞으로 당긴다.
    // iCloud에만 있는 사진은 뒤로 미루고 updateCaching()에서 미리 받기 시작한다.
    private func checkAvailability() {
        availabilityTask?.cancel()
        availabilityTask = nil
        guard filterType != .trash else { return }

        let generation = loadGeneration
        let targetSize = ReviewImageSpec.targetSize
        availabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, generation == self.loadGeneration,
                      let next = self.nextUncheckedPhoto() else { break }
                let isLocal = await Self.isLocallyAvailable(next.asset, targetSize: targetSize)
                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.localStatus[next.id] = isLocal
                if isLocal {
                    LocalAvailabilityCache.knownLocal.insert(next.id)
                } else {
                    await self.handleCloudPhoto(next, targetSize: targetSize, generation: generation)
                    guard !Task.isCancelled, generation == self.loadGeneration else { return }
                }
                self.moveLocalPhotosForward()
            }
            guard !Task.isCancelled, let self else { return }
            self.availabilityTask = nil
            let checked = self.localStatus.values
            imageLoadLog.notice("availability: \(checked.filter { $0 }.count, privacy: .public) local, \(checked.filter { !$0 }.count, privacy: .public) iCloud")
        }
    }

    // iCloud에만 있는 사진: 랜덤 100장이면 여분 중 기기에 있는 사진으로 바꾸고,
    // '기기에 있는 사진만' 모드면 목록에서 뺀다. 둘 다 아니면 뒤로 미뤄 미리 받는다.
    private func handleCloudPhoto(_ item: PhotoItem, targetSize: CGSize, generation: Int) async {
        if filterType == .random100, let replacement = await takeLocalReplacement(targetSize: targetSize) {
            guard generation == loadGeneration,
                  let index = photos.firstIndex(where: { $0.id == item.id }), index > currentIndex
            else { return }
            photos[index] = replacement
            localStatus[replacement.id] = true
            updateCaching()
        } else if onlyLocal,
                  let index = photos.firstIndex(where: { $0.id == item.id }), index > currentIndex {
            photos.remove(at: index)
            updateCaching()
        }
    }

    // 여분 후보를 최대 3장까지 확인해 기기에 있는 사진을 하나 꺼낸다.
    private func takeLocalReplacement(targetSize: CGSize) async -> PhotoItem? {
        for _ in 0..<3 {
            guard !randomReserve.isEmpty else { return nil }
            let candidate = randomReserve.removeFirst()
            if LocalAvailabilityCache.knownLocal.contains(candidate.id) { return candidate }
            if await Self.isLocallyAvailable(candidate.asset, targetSize: targetSize) {
                LocalAvailabilityCache.knownLocal.insert(candidate.id)
                return candidate
            }
        }
        return nil
    }

    private func nextUncheckedPhoto() -> PhotoItem? {
        let start = currentIndex + 1
        guard start < photos.count else { return nil }
        let end = min(photos.count, start + Self.availabilityLookahead)
        return photos[start..<end].first { localStatus[$0.id] == nil }
    }

    // 지금 보는 사진 다음부터: 기기에 있음 → 아직 모름 → iCloud 순으로, 같은 그룹 안의 순서는 유지한다.
    private func moveLocalPhotosForward() {
        let start = currentIndex + 1
        guard start < photos.count else { return }

        let upcoming = Array(photos[start...])
        let order = Self.availabilityOrder(ids: upcoming.map(\.id), status: localStatus)
        guard order != Array(upcoming.indices) else { return }
        photos.replaceSubrange(start..., with: order.map { upcoming[$0] })
        updateCaching()
    }

    /// 기기에 있음(true) → 아직 모름(nil) → iCloud(false) 순으로 정렬한 인덱스. 같은 그룹 안의 순서는 유지한다.
    nonisolated static func availabilityOrder(ids: [String], status: [String: Bool]) -> [Int] {
        func rank(_ id: String) -> Int {
            switch status[id] {
            case true?: return 0
            case nil: return 1
            case false?: return 2
            }
        }
        return ids.indices.sorted { (rank(ids[$0]), $0) < (rank(ids[$1]), $1) }
    }

    // 네트워크 없이 리뷰 화질 이미지를 받을 수 있으면 기기에 있는 것으로 본다.
    nonisolated private static func isLocallyAvailable(_ asset: PHAsset, targetSize: CGSize) async -> Bool {
        await withCheckedContinuation { continuation in
            let opt = PHImageRequestOptions()
            opt.isNetworkAccessAllowed = false
            opt.deliveryMode = .highQualityFormat // 결과 핸들러가 한 번만 불린다
            opt.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: opt
            ) { image, info in
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(returning: image != nil && !inCloud)
            }
        }
    }

    // MARK: - 이미지 캐싱
    // 현재 위치 기준 뒤 1장 / 앞 4장을 프리히팅하고, 그 뒤의 iCloud 사진 몇 장은 미리 받아 둔다.
    // 바뀐 부분만 캐시를 갱신한다. 너무 많이 미리 받으면 지금 보는 사진의 요청이 뒤로 밀린다.
    private func updateCaching() {
        var window: [PHAsset] = []
        if !photos.isEmpty {
            let range = max(0, currentIndex - 1)...min(photos.count - 1, currentIndex + 4)
            window = range.map { photos[$0].asset }

            if range.upperBound + 1 < photos.count {
                window += photos[(range.upperBound + 1)...]
                    .lazy
                    .filter { self.localStatus[$0.id] == false }
                    .prefix(cloudDownloadAhead)
                    .map(\.asset)
            }
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
        availabilityTask?.cancel()
        availabilityTask = nil
        sharedImageManager.stopCachingImagesForAllAssets()
        cachedAssets = []
    }
}
