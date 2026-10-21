//
//  mindPICTests.swift
//  mindPICTests
//
//  Created by Mindy on 12/5/25.
//

import Foundation
import Testing
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
