import Foundation
import Photos
import UIKit
import Vision

// MARK: - 비슷한 사진 묶음
struct SimilarGroup: Identifiable, Sendable {
    let id: String              // 묶음의 첫 사진 ID
    let items: [PhotoItem]      // 최신순
    let bestID: String          // 남기기를 추천하는 사진
}

// MARK: - 묶기 규칙 (Vision과 무관한 순수 로직)
enum SimilarPhotoGrouping {
    /// 촬영 시각이 maxGap 이내로 이어지는 구간들. 2장 이상인 구간만 돌려준다.
    /// dates는 시간순(오름차순이든 내림차순이든)으로 정렬돼 있어야 한다.
    static func timeClusters(dates: [Date], maxGap: TimeInterval) -> [Range<Int>] {
        guard !dates.isEmpty else { return [] }
        var clusters: [Range<Int>] = []
        var start = 0
        for index in 1...dates.count {
            let isBreak = index == dates.count
                || abs(dates[index].timeIntervalSince(dates[index - 1])) > maxGap
            guard isBreak else { continue }
            if index - start >= 2 { clusters.append(start..<index) }
            start = index
        }
        return clusters
    }

    /// 각 사진을 바로 앞 maxNeighbors장과 비교해, 비슷한 것끼리 이어진 묶음(2장 이상)의 인덱스 목록.
    /// A~B, B~C이면 A와 C가 직접 비슷하지 않아도 같은 묶음이 된다.
    static func groups(count: Int, maxNeighbors: Int, isSimilar: (Int, Int) -> Bool) -> [[Int]] {
        var parent = Array(0..<count)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for i in 0..<count {
            for j in max(0, i - maxNeighbors)..<i where isSimilar(j, i) {
                let (a, b) = (root(j), root(i))
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<count { members[root(i), default: []].append(i) }
        return members.values
            .filter { $0.count >= 2 }
            .sorted { $0[0] < $1[0] }
    }

    /// 남기기를 추천할 사진의 위치. 사용자가 즐겨찾기한 사진이 있으면 그중에서 고른다.
    /// 점수가 같으면 앞쪽(최신) 사진.
    static func bestIndex(scores: [Double], favorites: [Bool]) -> Int {
        let candidates = favorites.contains(true)
            ? scores.indices.filter { favorites[$0] }
            : Array(scores.indices)
        return candidates.max { a, b in
            scores[a] != scores[b] ? scores[a] < scores[b] : a > b
        } ?? 0
    }
}

// MARK: - 분석기 (기기 안에서 Vision으로 처리)
enum SimilarPhotoAnalyzer {
    enum Event: Sendable {
        case progress(done: Int, total: Int)
        case group(SimilarGroup)
    }

    // 이 시간 안에 이어서 찍은 사진끼리만 비교한다 (전체를 서로 비교하면 N²).
    static let maxGap: TimeInterval = 120
    // 연속 촬영이 길어도 바로 앞 몇 장과만 비교한다.
    static let maxNeighbors = 12
    // 특징 벡터 거리(revision 2, 0~2)가 이 값 이하면 비슷한 사진으로 본다. 작을수록 엄격하다.
    static let distanceThreshold: Float = 0.5

    /// since 이후(nil이면 전체) 사진을 최신순으로 분석해, 찾는 대로 묶음을 흘려보낸다.
    static func analyze(since: Date?, excluding: Set<String>) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await SimilarPhotoAnalyzer.run(since: since, excluding: excluding, continuation: continuation)
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

        var assets: [PHAsset] = []
        var dates: [Date] = []
        for index in 0..<result.count {
            let asset = result.object(at: index)
            guard !excluding.contains(asset.localIdentifier), let date = asset.creationDate else { continue }
            assets.append(asset)
            dates.append(date)
        }

        // 근처 시각에 찍은 사진이 없는 사진은 분석할 필요가 없다.
        let clusters = SimilarPhotoGrouping.timeClusters(dates: dates, maxGap: maxGap)
        let total = clusters.reduce(0) { $0 + $1.count }
        var done = 0
        continuation.yield(.progress(done: 0, total: total))

        for range in clusters {
            if Task.isCancelled { return }
            let members = Array(assets[range])

            var prints: [VNFeaturePrintObservation?] = []
            for asset in members {
                if Task.isCancelled { return }
                prints.append(await PhotoImageAnalysis.thumbnail(for: asset).flatMap(featurePrint))
            }

            let groups = SimilarPhotoGrouping.groups(count: members.count, maxNeighbors: maxNeighbors) { a, b in
                guard let pa = prints[a], let pb = prints[b], let d = distance(pa, pb) else { return false }
                return d <= distanceThreshold
            }

            for indices in groups {
                if Task.isCancelled { return }
                let groupAssets = indices.map { members[$0] }
                // 점수용 이미지는 묶음에 든 사진만 다시 받아 메모리를 아낀다.
                var images: [CGImage?] = []
                for asset in groupAssets { images.append(await PhotoImageAnalysis.thumbnail(for: asset)) }

                let best = SimilarPhotoGrouping.bestIndex(
                    scores: qualityScores(images),
                    favorites: groupAssets.map(\.isFavorite)
                )
                let items = groupAssets.map(PhotoItem.init(asset:))
                continuation.yield(.group(SimilarGroup(id: items[0].id, items: items, bestID: items[best].id)))
            }

            done += range.count
            continuation.yield(.progress(done: done, total: total))
        }
    }

    private static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    private static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value: Float = 0
        do {
            try a.computeDistance(&value, to: b)
        } catch {
            return nil
        }
        return value
    }

    // MARK: 잘 나온 사진 점수
    // 묶음 안에서는 같은 기준으로 비교해야 하므로 기준을 하나 골라 모두에 적용한다.
    // iOS 18: 미적 점수 → 얼굴이 있으면 얼굴 품질 → 그 외 선명도
    private static func qualityScores(_ images: [CGImage?]) -> [Double] {
        if #available(iOS 18.0, *) {
            let aesthetics = images.map { $0.flatMap(PhotoImageAnalysis.aesthetics)?.overall }
            if aesthetics.contains(where: { $0 != nil }) {
                return aesthetics.map { $0 ?? -.infinity }
            }
        }
        let faces = images.map { $0.flatMap(PhotoImageAnalysis.faceQuality) }
        if faces.contains(where: { $0 != nil }) {
            return faces.map { $0 ?? 0 }
        }
        return images.map { $0.map(PhotoImageAnalysis.sharpness) ?? 0 }
    }
}
