import Combine
import Photos
import UIKit

class PhotoReviewViewModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false

    @Published var filterType: PhotoFilterType = .random100

    @Published var selectedYearsBack: Int = 1
    @Published var selectedMonthStartDate: Date = Date()

    @Published var libraryStartDate: Date?

    // 본 적 있는 사진 ID 저장
    @Published var seenPhotoIDs: Set<String> = []
    private let seenKey = "seen_photos"

    // 휴지통 사진 ID 저장
    @Published var trashedPhotoIDs: Set<String> = []
    private let trashKey = trashedPhotosKey

    // 안 본 사진만 보기 토글
    @Published var onlyUnseen: Bool = false

    // ✅ 랜덤100 다 봤을 때 팝업 띄우기 트리거
    @Published var shouldAskForNewRandom: Bool = false

    init() {
        loadSeenPhotos()
        loadTrashedPhotos()
    }

    var currentPhoto: PhotoItem? {
        guard currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var currentDateString: String? {
        guard let date = currentPhoto?.asset.creationDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - Seen 저장/로딩
    private func loadSeenPhotos() {
        if let arr = UserDefaults.standard.array(forKey: seenKey) as? [String] {
            seenPhotoIDs = Set(arr)
        }
    }

    private func saveSeenPhotos() {
        UserDefaults.standard.set(Array(seenPhotoIDs), forKey: seenKey)
    }

    private func loadTrashedPhotos() {
        if let arr = UserDefaults.standard.array(forKey: trashKey) as? [String] {
            trashedPhotoIDs = Set(arr)
        }
    }

    private func saveTrashedPhotos() {
        UserDefaults.standard.set(Array(trashedPhotoIDs), forKey: trashKey)
    }

    private func markCurrentAsSeen() {
        if let id = currentPhoto?.id {
            if !seenPhotoIDs.contains(id) {
                seenPhotoIDs.insert(id)
                saveSeenPhotos()
            }
        }
    }

    // MARK: - 필터 공통 후처리 (안 본 사진만 보기 적용)
    private func applyPostFilters(to items: [PhotoItem]) -> [PhotoItem] {
        var result = items
        if case .trash = filterType {
            result = result.filter { trashedPhotoIDs.contains($0.id) }
            return result
        }
        result = result.filter { !trashedPhotoIDs.contains($0.id) }
        if onlyUnseen {
            result = result.filter { !seenPhotoIDs.contains($0.id) }
        }
        return result
    }

    private func finishLoading(with items: [PhotoItem]) {
        let filtered = applyPostFilters(to: items)
        self.photos = filtered
        self.currentIndex = 0
        self.isLoading = false
        self.shouldAskForNewRandom = false
        self.updateCaching()
    }

    // MARK: - 현재 선택된 필터 다시 적용
    func reloadByFilter() {
        switch filterType {
        case .random100:
            loadRandom100()
        case .yearsAgo(let y):
            loadYearsAgoToday(yearsBack: y)
        case .monthRange(let d):
            loadMonthRange(from: d)
        case .recentDays(let d):
            loadRecent(days: d)
        case .peoplePortrait:
            loadPeoplePortrait()
        case .nonFavorite:
            loadNonFavorite()
        case .screenshot:
            loadScreenshot()
        case .burst:
            loadBurst()
        case .trash:
            loadTrash()
        }
    }

    // MARK: - 1) 랜덤 100장
    func selectRandom100() {
        filterType = .random100
        loadRandom100()
    }

    private func loadRandom100(limit: Int = 100) {
        isLoading = true
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        items.shuffle()
        if items.count > limit {
            items = Array(items.prefix(limit))
        }

        DispatchQueue.main.async {
            self.finishLoading(with: items)
        }
    }

    // MARK: - 2) N년 전 오늘 (±15일)
    func selectYearsAgo(yearsBack: Int) {
        selectedYearsBack = yearsBack
        filterType = .yearsAgo(yearsBack)
        loadYearsAgoToday(yearsBack: yearsBack)
    }

    private func loadYearsAgoToday(yearsBack: Int, dayRange: Int = 15) {
        isLoading = true
        let cal = Calendar.current
        let now = Date()
        guard let center = cal.date(byAdding: .year, value: -yearsBack, to: now),
              let start = cal.date(byAdding: .day, value: -dayRange, to: center),
              let end   = cal.date(byAdding: .day, value:  dayRange, to: center)
        else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.predicate = NSPredicate(format:"creationDate >= %@ AND creationDate <= %@",
                                    start as NSDate, end as NSDate)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 3) 연/월 → 1달
    func selectMonthRange(from start: Date) {
        selectedMonthStartDate = start
        filterType = .monthRange(start)
        loadMonthRange(from: start)
    }

    private func loadMonthRange(from start: Date) {
        isLoading = true
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.predicate = NSPredicate(format:"creationDate >= %@ AND creationDate <= %@",
                                    start as NSDate, end as NSDate)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // 🔹 랜덤 1개월 (전체 기간) - 기존 로직 유지
    func selectRandomMonthFromLibrary() {
        ensureLibraryStartDate { [weak self] in
            guard let self = self, let libStart = self.libraryStartDate else { return }

            func pickRandomMonth() {
                let cal = Calendar.current
                let now = Date()

                var startComp = cal.dateComponents([.year, .month], from: libStart)
                startComp.day = 1
                guard let firstMonthStart = cal.date(from: startComp) else { return }

                let monthDiff = cal.dateComponents([.month], from: firstMonthStart, to: now).month ?? 0
                let maxOffset = max(monthDiff, 0)
                let randomOffset = Int.random(in: 0...maxOffset)

                if let randomMonthStart = cal.date(byAdding: .month, value: randomOffset, to: firstMonthStart) {
                    self.loadMonthRangeAndCheck(start: randomMonthStart, retry: pickRandomMonth)
                }
            }

            pickRandomMonth()
        }
    }

    private func loadMonthRangeAndCheck(start: Date, retry: @escaping () -> Void) {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return }

        isLoading = true

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.predicate = NSPredicate(format:"creationDate >= %@ AND creationDate <= %@",
                                    start as NSDate, end as NSDate)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async {
            if items.isEmpty { retry() }
            else { self.finishLoading(with: items) }
        }
    }

    private func ensureLibraryStartDate(completion: @escaping () -> Void) {
        if libraryStartDate != nil { completion(); return }

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        opt.fetchLimit = 1

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        if let asset = result.firstObject, let date = asset.creationDate {
            DispatchQueue.main.async { self.libraryStartDate = date; completion() }
        } else {
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - 4) 최근 N일
    func selectRecent(days: Int) {
        filterType = .recentDays(days)
        loadRecent(days: days)
    }

    private func loadRecent(days: Int) {
        isLoading = true
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: now) else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.predicate = NSPredicate(format:"creationDate >= %@", start as NSDate)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 5) 사람(Portrait, Depth Effect)
    func selectPeoplePortrait() {
        filterType = .peoplePortrait
        loadPeoplePortrait()
    }

    private func loadPeoplePortrait() {
        isLoading = true
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending:false)]
        opt.predicate = NSPredicate(format:"(mediaSubtype & %d) != 0",
                                    PHAssetMediaSubtype.photoDepthEffect.rawValue)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items: [PhotoItem] = []
        result.enumerateObjects { asset,_,_ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 6) 즐겨찾기 안 된 사진
    func selectNonFavorite() {
        filterType = .nonFavorite
        loadNonFavorite()
    }

    private func loadNonFavorite() {
        isLoading = true
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending:false)]
        opt.predicate = NSPredicate(format:"isFavorite == NO")

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items:[PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 7) 스크린샷
    func selectScreenshot() {
        filterType = .screenshot
        loadScreenshot()
    }

    private func loadScreenshot() {
        isLoading = true
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending:false)]
        opt.predicate = NSPredicate(format:"(mediaSubtype & %d) != 0",
                                    PHAssetMediaSubtype.photoScreenshot.rawValue)

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items:[PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 8) 버스트(연사)
    func selectBurst() {
        filterType = .burst
        loadBurst()
    }

    private func loadBurst() {
        isLoading = true
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending:false)]

        let result = PHAsset.fetchAssets(with: .image, options: opt)
        var items:[PhotoItem] = []
        result.enumerateObjects { asset, _, _ in
            if asset.representsBurst || asset.burstIdentifier != nil {
                items.append(PhotoItem(id: asset.localIdentifier, asset: asset))
            }
        }

        DispatchQueue.main.async { self.finishLoading(with: items) }
    }

    // MARK: - 9) 휴지통
    func selectTrash() {
        filterType = .trash
        loadTrash()
    }

    private func loadTrash() {
        isLoading = true
        let ids = Array(trashedPhotoIDs)
        guard !ids.isEmpty else {
            DispatchQueue.main.async { self.finishLoading(with: []) }
            return
        }

        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending:false)]

        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: opt)
        var items: [PhotoItem] = []
        var foundIDs: Set<String> = []
        result.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            foundIDs.insert(id)
            items.append(PhotoItem(id: id, asset: asset))
        }

        DispatchQueue.main.async {
            if foundIDs != self.trashedPhotoIDs {
                self.trashedPhotoIDs = foundIDs
                self.saveTrashedPhotos()
            }
            self.finishLoading(with: items)
        }
    }

    // MARK: - 이동 기능
    private func advance(by step: Int) {
        guard !photos.isEmpty else { return }

        // ✅ 랜덤100에서 마지막 사진인데 "다음" 시도하면 팝업 요청
        if step > 0,
           case .random100 = filterType,
           currentIndex >= photos.count - 1 {
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
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = true
        }
    }

    func delete() {
        guard let current = currentPhoto else { return }
        markCurrentAsSeen()
        let id = current.id
        if !trashedPhotoIDs.contains(id) {
            trashedPhotoIDs.insert(id)
            saveTrashedPhotos()
        }

        let removeIndex = currentIndex
        photos.remove(at: removeIndex)
        if photos.isEmpty {
            currentIndex = 0
            if case .random100 = filterType { shouldAskForNewRandom = true }
        } else if removeIndex >= photos.count {
            currentIndex = photos.count - 1
        }
        updateCaching()
    }

    func emptyTrash() {
        let ids = Array(trashedPhotoIDs)
        guard !ids.isEmpty else { return }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else {
            trashedPhotoIDs.removeAll()
            saveTrashedPhotos()
            if case .trash = filterType { finishLoading(with: []) }
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, _ in
            DispatchQueue.main.async {
                guard success else { return }
                self.trashedPhotoIDs.removeAll()
                self.saveTrashedPhotos()
                if case .trash = self.filterType {
                    self.finishLoading(with: [])
                }
            }
        }
    }

    func restore(photoID: String) {
        guard trashedPhotoIDs.contains(photoID) else { return }
        trashedPhotoIDs.remove(photoID)
        saveTrashedPhotos()

        if case .trash = filterType {
            if let index = photos.firstIndex(where: { $0.id == photoID }) {
                photos.remove(at: index)
                if photos.isEmpty {
                    currentIndex = 0
                } else if currentIndex >= photos.count {
                    currentIndex = photos.count - 1
                }
            }
        }
    }

    // MARK: - 이미지 캐싱
    private func updateCaching() {
        sharedImageManager.stopCachingImagesForAllAssets()
        guard !photos.isEmpty else { return }

        let preheatRange = max(0, currentIndex - 5)...min(photos.count - 1, currentIndex + 10)
        let assetsToCache = preheatRange.map { photos[$0].asset }

        let screen = UIScreen.main
        let size = CGSize(width: screen.bounds.width * screen.scale,
                          height: screen.bounds.height * screen.scale)

        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true
        opt.deliveryMode = .highQualityFormat
        opt.resizeMode = .fast

        sharedImageManager.startCachingImages(
            for: assetsToCache,
            targetSize: size,
            contentMode: .aspectFill,
            options: opt
        )
    }
}
