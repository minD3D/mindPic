import Foundation
import Photos
import SwiftUI

// MARK: - 정리 추천 이유
enum CleanupReason: String, CaseIterable, Identifiable, Sendable {
    case lowQuality   // 미적 점수가 낮음 (iOS 18)
    case blurry       // 흔들림·초점 나감 (iOS 17)
    case dark         // 너무 어두움 (주머니 속, 실수로 찍힘)
    case bright       // 너무 밝음 (하얗게 날아감)
    case utility      // 영수증·문서·메모 같은 기록용 사진 (iOS 18)
    case screenshot   // 스크린샷

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .lowQuality: return "아쉬운 사진"
        case .blurry: return "흐림"
        case .dark: return "어두움"
        case .bright: return "너무 밝음"
        case .utility: return "기록용"
        case .screenshot: return "스크린샷"
        }
    }

    var systemImage: String {
        switch self {
        case .lowQuality: return "hand.thumbsdown"
        case .blurry: return "camera.aperture"
        case .dark: return "moon"
        case .bright: return "sun.max"
        case .utility: return "doc.text"
        case .screenshot: return "iphone"
        }
    }
}

// MARK: - 판단 규칙 (Vision과 무관한 순수 로직)
struct PhotoMetrics: Sendable {
    var brightness: Double              // 0~1
    var sharpness: Double?              // 0~1, iOS 17에서만 계산
    var aestheticScore: Double?         // -1~1, iOS 18
    var isUtility: Bool = false         // iOS 18
    var isScreenshot: Bool = false
}

enum CleanupRules {
    // 값이 클수록 추천이 엄격해진다(적게 나온다). 실제 사진으로 조정할 수 있다.
    static let darkBelow = 0.08
    static let brightAbove = 0.93
    // 360px 썸네일 기준: 또렷한 사진은 0.0077 이상, 흔들리거나 초점이 나간 사진은 0.005 이하.
    // 살짝 흐린 사진(0.007 안팎)은 매끈한 부분이 넓은 또렷한 사진과 구분되지 않아, 또렷한 사진을 추천하지 않는 쪽을 택했다.
    static let blurryBelow = 0.006
    static let lowQualityBelow = -0.3

    /// 정리할 만한 이유들. 비어 있으면 추천하지 않는다. 중요한 이유가 먼저 온다.
    static func reasons(for m: PhotoMetrics) -> [CleanupReason] {
        var reasons: [CleanupReason] = []
        if m.isScreenshot { reasons.append(.screenshot) }
        if m.isUtility && !m.isScreenshot { reasons.append(.utility) }
        if m.brightness < darkBelow { reasons.append(.dark) }
        if m.brightness > brightAbove { reasons.append(.bright) }
        if let score = m.aestheticScore {
            // 기록용 사진은 원래 점수가 낮으니 이유를 하나만 붙인다.
            if score < lowQualityBelow && !m.isUtility && !m.isScreenshot { reasons.append(.lowQuality) }
        } else if let sharpness = m.sharpness, sharpness < blurryBelow,
                  !m.isScreenshot, m.brightness >= darkBelow {
            // 어두운 사진은 윤곽선이 약해 흐린 것처럼 보이므로 '어두움'만 붙인다.
            reasons.append(.blurry)
        }
        return reasons
    }
}

struct CleanupSuggestion: Identifiable, Sendable {
    let item: PhotoItem
    let reasons: [CleanupReason]
    var id: String { item.id }
}

// MARK: - 분석기
enum CleanupSuggestionAnalyzer {
    enum Event: Sendable {
        case progress(done: Int, total: Int)
        case suggestion(CleanupSuggestion)
    }

    // 동시에 분석할 사진 수. Vision 요청은 서로 독립적이라 나눠서 처리하면 빨라진다.
    static let concurrency = 3

    /// since 이후(nil이면 전체) 사진을 최신순으로 분석해, 정리할 만한 사진을 찾는 대로 흘려보낸다.
    /// 즐겨찾기한 사진은 추천하지 않는다.
    static func analyze(since: Date?, excluding: Set<String>) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await CleanupSuggestionAnalyzer.run(since: since, excluding: excluding, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        since: Date?, excluding: Set<String>, continuation: AsyncStream<Event>.Continuation
    ) async {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let since {
            options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)
        }
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var items: [PhotoItem] = []
        for index in 0..<result.count {
            let asset = result.object(at: index)
            guard !asset.isFavorite, !excluding.contains(asset.localIdentifier) else { continue }
            items.append(PhotoItem(asset: asset))
        }

        let total = items.count
        var done = 0
        continuation.yield(.progress(done: 0, total: total))

        // 몇 장씩 나눠 동시에 분석하고, 묶음 안의 순서(최신순)대로 내보낸다.
        var start = 0
        while start < total {
            if Task.isCancelled { return }
            let batch = Array(items[start..<min(start + concurrency, total)])
            let results = await withTaskGroup(of: (Int, CleanupSuggestion?).self) { group in
                for (offset, item) in batch.enumerated() {
                    group.addTask {
                        let suggestion = await CleanupSuggestionAnalyzer.suggestion(for: item)
                        return (offset, suggestion)
                    }
                }
                var collected: [(Int, CleanupSuggestion?)] = []
                for await result in group { collected.append(result) }
                return collected.sorted { $0.0 < $1.0 }
            }
            for case let (_, suggestion?) in results {
                continuation.yield(.suggestion(suggestion))
            }
            start += batch.count
            done += batch.count
            continuation.yield(.progress(done: done, total: total))
        }
    }

    private static func suggestion(for item: PhotoItem) async -> CleanupSuggestion? {
        let isScreenshot = item.asset.mediaSubtypes.contains(.photoScreenshot)
        guard let image = await PhotoImageAnalysis.thumbnail(for: item.asset) else { return nil }

        var metrics = PhotoMetrics(brightness: PhotoImageAnalysis.brightness(image), isScreenshot: isScreenshot)
        if #available(iOS 18.0, *), let aesthetics = PhotoImageAnalysis.aesthetics(image) {
            metrics.aestheticScore = aesthetics.overall
            metrics.isUtility = aesthetics.isUtility
        } else {
            metrics.sharpness = PhotoImageAnalysis.sharpness(image)
            // iOS 17: 분류 라벨로 기록용(문서·영수증 등)을 판단한다. 결과는 종류 필터와 함께 쓰도록 저장된다.
            let categories = await PhotoCategoryIndex.shared.categories(for: item, image: image)
            metrics.isUtility = categories?.contains(.document) ?? false
        }

        let reasons = CleanupRules.reasons(for: metrics)
        return reasons.isEmpty ? nil : CleanupSuggestion(item: item, reasons: reasons)
    }
}
