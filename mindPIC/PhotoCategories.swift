import CoreGraphics
import Foundation
import Photos
import SwiftUI

// MARK: - 사진 종류 (Vision 분류 라벨을 묶은 것)
enum PhotoCategory: String, CaseIterable, Identifiable, Sendable {
    case food, document, animal, nature

    var id: Self { self }

    // 필터 칩·제목에 쓰는 이름
    var title: String {
        switch self {
        case .food: return String(localized: "음식")
        case .document: return String(localized: "문서·텍스트")
        case .animal: return String(localized: "동물")
        case .nature: return String(localized: "풍경")
        }
    }

    var systemImage: String {
        switch self {
        case .food: return "fork.knife"
        case .document: return "doc.text"
        case .animal: return "pawprint"
        case .nature: return "mountain.2"
        }
    }

    // 이 종류로 보는 Vision 분류 라벨. 라벨은 상위·하위 개념이 함께 붙으므로 대표 라벨 위주로 고른다.
    // 모두 VNClassifyImageRequest.supportedIdentifiers()에 있는 값이어야 한다 (단위 테스트로 확인).
    var labels: Set<String> {
        switch self {
        case .food:
            return ["food", "drink", "dessert", "baked_goods", "fruit", "vegetable", "meat", "seafood",
                    "salad", "soup", "pizza", "pasta", "sushi", "sandwich", "cake", "coffee", "cocktail"]
        case .document:
            // 기록용 사진 판별(iOS 17)에도 쓰인다.
            return ["document", "receipt", "printed_page", "handwriting", "whiteboard", "chalkboard",
                    "flipchart", "sticky_note", "newspaper", "magazine", "diagram", "chart", "ticket",
                    "coupon", "envelope", "calendar", "passport", "checkbook"]
        case .animal:
            // 'mammal'은 범위가 넓어 넣지 않는다.
            return ["animal", "dog", "cat", "canine", "feline", "kitten", "bird", "fish", "insect",
                    "reptile", "horse", "rabbit", "rodent"]
        case .nature:
            // 'sky'는 도시 사진에도 붙어 넣지 않는다.
            return ["mountain", "beach", "ocean", "lake", "river", "waterfall", "forest", "desert",
                    "canyon", "cliff", "glacier", "hill", "shore", "sunset_sunrise", "night_sky",
                    "aurora", "sand_dune", "volcano", "island"]
        }
    }

    // 이 신뢰도 이상인 라벨만 본다. 높일수록 엄격해진다.
    static let minimumConfidence: Float = 0.5

    static func categories(for labels: Set<String>) -> Set<PhotoCategory> {
        Set(allCases.filter { !$0.labels.isDisjoint(with: labels) })
    }
}

// MARK: - 사진 종류 색인
// 사진마다 분류는 한 번만 하고 결과를 기기에 저장해, 다음부터는 바로 찾는다.
actor PhotoCategoryIndex {
    static let shared = PhotoCategoryIndex()

    // 라벨 묶음(PhotoCategory.labels)이나 기준을 바꾸면 올려서 저장된 결과를 버린다.
    private static let version = 1
    // 동시에 분류할 사진 수
    private static let batchSize = 4

    private struct Stored: Codable {
        let version: Int
        let entries: [String: [String]]
    }

    private var entries: [String: [String]] = [:]   // 사진 ID → 종류 rawValue
    private var isLoaded = false
    private var unsavedCount = 0

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo-categories.json")
    }

    /// 사진 한 장의 종류. 분류한 적 없으면 지금 분류해 저장한다. 기기에 이미지가 없으면 nil.
    func categories(for item: PhotoItem, image: CGImage? = nil) async -> Set<PhotoCategory>? {
        loadIfNeeded()
        if let cached = cached(item.id) { return cached }
        guard let computed = await Self.classify(item, image: image) else { return nil }
        store(computed, for: item.id)
        return computed
    }

    /// 최신 사진부터 훑으며 해당 종류 사진을 최대 limit장 찾는다.
    /// progress(확인한 수, 전체 수)는 몇 장마다 불린다.
    func find(
        _ category: PhotoCategory,
        limit: Int,
        isIncluded: @Sendable (String) -> Bool,
        progress: @Sendable (Int, Int) -> Void
    ) async -> [PhotoItem] {
        loadIfNeeded()
        defer { save() }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        let total = result.count

        var found: [PhotoItem] = []
        var index = 0
        while index < total && found.count < limit {
            if Task.isCancelled { break }

            var batch: [PhotoItem] = []
            while batch.count < Self.batchSize && index < total {
                let asset = result.object(at: index)
                index += 1
                if isIncluded(asset.localIdentifier) { batch.append(PhotoItem(asset: asset)) }
            }

            // 아직 분류하지 않은 사진만 동시에 분류한다.
            let missing = batch.filter { cached($0.id) == nil }
            if !missing.isEmpty {
                let computed = await withTaskGroup(of: (String, Set<PhotoCategory>?).self) { group in
                    for item in missing {
                        group.addTask {
                            let categories = await PhotoCategoryIndex.classify(item, image: nil)
                            return (item.id, categories)
                        }
                    }
                    var results: [(String, Set<PhotoCategory>?)] = []
                    for await result in group { results.append(result) }
                    return results
                }
                for case let (id, categories?) in computed { store(categories, for: id) }
            }

            for item in batch where cached(item.id)?.contains(category) == true {
                found.append(item)
                if found.count >= limit { break }
            }
            progress(index, total)
        }
        return found
    }

    // MARK: 분류
    private static func classify(_ item: PhotoItem, image: CGImage?) async -> Set<PhotoCategory>? {
        var cgImage = image
        if cgImage == nil { cgImage = await PhotoImageAnalysis.thumbnail(for: item.asset) }
        guard let cgImage else { return nil }
        let labels = PhotoImageAnalysis.classificationLabels(cgImage, minimumConfidence: PhotoCategory.minimumConfidence)
        return PhotoCategory.categories(for: labels)
    }

    // MARK: 저장
    private func cached(_ id: String) -> Set<PhotoCategory>? {
        entries[id].map { Set($0.compactMap(PhotoCategory.init(rawValue:))) }
    }

    private func store(_ categories: Set<PhotoCategory>, for id: String) {
        entries[id] = categories.map(\.rawValue).sorted()
        unsavedCount += 1
        if unsavedCount >= 200 { save() }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.version
        else { return }
        entries = stored.entries
    }

    private func save() {
        guard unsavedCount > 0 else { return }
        unsavedCount = 0
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Stored(version: Self.version, entries: entries)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
