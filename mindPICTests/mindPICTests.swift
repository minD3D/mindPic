//
//  mindPICTests.swift
//  mindPICTests
//
//  Created by Mindy on 12/5/25.
//

import Foundation
import Testing
import Vision
@testable import mindPIC

struct ReviewStateStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "mindPICTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func persistsSeenAndTrashAcrossInstances() {
        let defaults = makeDefaults()
        let store = ReviewStateStore(defaults: defaults)
        store.markSeen("a")
        store.addToTrash("b")
        store.addToTrash("c")

        let reloaded = ReviewStateStore(defaults: defaults)
        #expect(reloaded.seenIDs == ["a"])
        #expect(reloaded.trashedIDs == ["b", "c"])
        #expect(ReviewStateStore.trashCount(in: defaults) == 2)
    }

    @Test func removeFromTrashOnlyRemovesGivenIDs() {
        let defaults = makeDefaults()
        let store = ReviewStateStore(defaults: defaults)
        ["a", "b", "c"].forEach(store.addToTrash)

        store.removeFromTrash(["a", "missing"])

        #expect(store.trashedIDs == ["b", "c"])
        #expect(ReviewStateStore(defaults: defaults).trashedIDs == ["b", "c"])
    }

    @Test func readsLegacyArrayFormat() {
        let defaults = makeDefaults()
        defaults.set(["x", "y", "x"], forKey: ReviewStateStore.trashedKey)

        #expect(ReviewStateStore(defaults: defaults).trashedIDs == ["x", "y"])
    }
}

struct FreedBytesTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "mindPICTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func accumulatesAcrossInstances() {
        let defaults = makeDefaults()
        ReviewStateStore(defaults: defaults).addFreedBytes(1_500)
        ReviewStateStore(defaults: defaults).addFreedBytes(2_500)
        #expect(ReviewStateStore.freedBytes(in: defaults) == 4_000)
    }

    @Test func ignoresZeroAndResetsWithResetAll() {
        let defaults = makeDefaults()
        let store = ReviewStateStore(defaults: defaults)
        store.addFreedBytes(0)
        #expect(ReviewStateStore.freedBytes(in: defaults) == 0)
        store.addFreedBytes(10)
        ReviewStateStore.resetAll(in: defaults)
        #expect(ReviewStateStore.freedBytes(in: defaults) == 0)
    }
}

struct RandomIndicesTests {

    @Test func returnsAtMostLimitUniqueIndices() {
        let picked = PhotoReviewViewModel.randomIndices(count: 1000, limit: 100) { _ in true }
        #expect(picked.count == 100)
        #expect(Set(picked).count == 100)
        #expect(picked.allSatisfy { (0..<1000).contains($0) })
    }

    @Test func skipsExcludedIndices() {
        let picked = PhotoReviewViewModel.randomIndices(count: 300, limit: 100) { $0.isMultiple(of: 3) }
        #expect(picked.count == 100)
        #expect(picked.allSatisfy { $0.isMultiple(of: 3) })
    }

    @Test func returnsEverythingWhenFewerThanLimit() {
        let picked = PhotoReviewViewModel.randomIndices(count: 10, limit: 100) { $0 != 3 }
        #expect(Set(picked) == Set((0..<10).filter { $0 != 3 }))
    }

    @Test func handlesEmptyLibrary() {
        #expect(PhotoReviewViewModel.randomIndices(count: 0, limit: 100) { _ in true }.isEmpty)
    }
}

struct AvailabilityOrderTests {

    @Test func putsLocalFirstThenUnknownThenCloud() {
        let ids = ["a", "b", "c", "d", "e"]
        let status: [String: Bool] = ["a": false, "b": true, "d": true, "e": false]
        let order = PhotoReviewViewModel.availabilityOrder(ids: ids, status: status)
        #expect(order.map { ids[$0] } == ["b", "d", "c", "a", "e"])
    }

    @Test func keepsOrderWhenNothingIsKnown() {
        let ids = ["a", "b", "c"]
        #expect(PhotoReviewViewModel.availabilityOrder(ids: ids, status: [:]) == [0, 1, 2])
    }

    @Test func handlesEmptyList() {
        #expect(PhotoReviewViewModel.availabilityOrder(ids: [], status: ["a": true]).isEmpty)
    }
}

struct SimilarPhotoGroupingTests {

    private func dates(_ seconds: [TimeInterval]) -> [Date] {
        seconds.map { Date(timeIntervalSince1970: $0) }
    }

    @Test func timeClustersSplitOnLargeGaps() {
        // 0,30,60 / 1000 (혼자) / 5000,5100
        let clusters = SimilarPhotoGrouping.timeClusters(dates: dates([0, 30, 60, 1000, 5000, 5100]), maxGap: 120)
        #expect(clusters == [0..<3, 4..<6])
    }

    @Test func timeClustersWorkNewestFirst() {
        let clusters = SimilarPhotoGrouping.timeClusters(dates: dates([5100, 5000, 1000, 60, 30, 0]), maxGap: 120)
        #expect(clusters == [0..<2, 3..<6])
    }

    @Test func timeClustersIgnoreSinglePhotos() {
        #expect(SimilarPhotoGrouping.timeClusters(dates: dates([0, 500, 1000]), maxGap: 120).isEmpty)
        #expect(SimilarPhotoGrouping.timeClusters(dates: dates([0]), maxGap: 120).isEmpty)
        #expect(SimilarPhotoGrouping.timeClusters(dates: [], maxGap: 120).isEmpty)
    }

    @Test func groupsAreTransitive() {
        // 0~1, 1~2 → {0,1,2}, 3과 4는 따로, 4~5 → {4,5}
        let similar: Set<[Int]> = [[0, 1], [1, 2], [4, 5]]
        let groups = SimilarPhotoGrouping.groups(count: 6, maxNeighbors: 10) { similar.contains([$0, $1]) }
        #expect(groups == [[0, 1, 2], [4, 5]])
    }

    @Test func groupsOnlyCompareNearbyNeighbors() {
        // 0과 3이 비슷해도 maxNeighbors가 2면 비교하지 않는다.
        let groups = SimilarPhotoGrouping.groups(count: 4, maxNeighbors: 2) { $0 == 0 && $1 == 3 }
        #expect(groups.isEmpty)
    }

    @Test func bestIndexPicksHighestScore() {
        #expect(SimilarPhotoGrouping.bestIndex(scores: [0.2, 0.9, 0.5], favorites: [false, false, false]) == 1)
    }

    @Test func bestIndexPrefersFavorites() {
        #expect(SimilarPhotoGrouping.bestIndex(scores: [0.2, 0.9, 0.5], favorites: [true, false, true]) == 2)
    }

    @Test func bestIndexBreaksTiesWithFirst() {
        #expect(SimilarPhotoGrouping.bestIndex(scores: [0.5, 0.5, 0.1], favorites: [false, false, false]) == 0)
    }
}

struct ReviewStateStoreBatchTests {

    @Test func addAllToTrashAndMarkAllSeenPersist() {
        let suite = "mindPICTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReviewStateStore(defaults: defaults)
        store.addAllToTrash(["a", "b"])
        store.markAllSeen(["a", "b", "c"])

        let reloaded = ReviewStateStore(defaults: defaults)
        #expect(reloaded.trashedIDs == ["a", "b"])
        #expect(reloaded.seenIDs == ["a", "b", "c"])
    }
}

struct CleanupRulesTests {

    private func metrics(brightness: Double = 0.5, sharpness: Double? = nil, aesthetic: Double? = nil,
                         utility: Bool = false, screenshot: Bool = false) -> PhotoMetrics {
        PhotoMetrics(brightness: brightness, sharpness: sharpness, aestheticScore: aesthetic,
                     isUtility: utility, isScreenshot: screenshot)
    }

    @Test func normalPhotoIsNotSuggested() {
        #expect(CleanupRules.reasons(for: metrics(sharpness: 0.1)).isEmpty)
        #expect(CleanupRules.reasons(for: metrics(aesthetic: 0.4)).isEmpty)
    }

    @Test func darkAndBrightPhotos() {
        #expect(CleanupRules.reasons(for: metrics(brightness: 0.02, sharpness: 0.1)) == [.dark])
        #expect(CleanupRules.reasons(for: metrics(brightness: 0.98, sharpness: 0.1)) == [.bright])
    }

    @Test func blurryOnlyWithoutAestheticScore() {
        #expect(CleanupRules.reasons(for: metrics(sharpness: 0.005)) == [.blurry])
        // iOS 18에서는 미적 점수가 흐림까지 반영하므로 선명도를 보지 않는다.
        #expect(CleanupRules.reasons(for: metrics(sharpness: 0.005, aesthetic: 0.4)).isEmpty)
    }

    @Test func darkPhotoIsNotAlsoBlurry() {
        #expect(CleanupRules.reasons(for: metrics(brightness: 0.03, sharpness: 0.001)) == [.dark])
    }

    @Test func lowQualityFromAestheticScore() {
        #expect(CleanupRules.reasons(for: metrics(aesthetic: -0.6)) == [.lowQuality])
    }

    @Test func utilityAndScreenshotGetOneMainReason() {
        #expect(CleanupRules.reasons(for: metrics(aesthetic: -0.8, utility: true)) == [.utility])
        #expect(CleanupRules.reasons(for: metrics(aesthetic: -0.8, utility: true, screenshot: true)) == [.screenshot])
        #expect(CleanupRules.reasons(for: metrics(sharpness: 0.001, screenshot: true)) == [.screenshot])
    }
}

struct PhotoCategoryTests {

    // 분류 라벨 이름이 Vision에 실제로 있는지 확인한다 (오타나 없는 라벨이면 그 종류는 절대 찾을 수 없다).
    @Test func allLabelsAreKnownToVision() throws {
        let supported = Set(try VNClassifyImageRequest().supportedIdentifiers())
        for category in PhotoCategory.allCases {
            #expect(!category.labels.isEmpty, "\(category) has no labels")
            let unknown = category.labels.subtracting(supported)
            #expect(unknown.isEmpty, "\(category): unknown labels \(unknown.sorted())")
        }
    }

    @Test func mapsLabelsToCategories() {
        for category in PhotoCategory.allCases {
            guard let label = category.labels.first else { continue }
            #expect(PhotoCategory.categories(for: [label]).contains(category))
        }
        #expect(PhotoCategory.categories(for: ["no_such_label"]).isEmpty)
        #expect(PhotoCategory.categories(for: []).isEmpty)
    }
}
