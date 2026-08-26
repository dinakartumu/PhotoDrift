import Testing
@testable import PhotoDrift

struct PrefetchCandidateTests {

    private func entry(_ id: String) -> UnifiedPool.PoolEntry {
        UnifiedPool.PoolEntry(id: id, sourceType: .applePhotos, albumID: "album")
    }

    @Test func recentlyShownAssetsAreNotPrefetched() {
        let pool = ["a", "b", "c", "d"].map(entry)
        let candidates = ShuffleEngine.prefetchCandidates(from: pool, excluding: ["a", "c"])
        #expect(!candidates.contains { $0.id == "a" })
        #expect(!candidates.contains { $0.id == "c" })
    }

    @Test func atMostTheLimitIsPrefetched() {
        let pool = (1...20).map { entry("asset-\($0)") }
        #expect(ShuffleEngine.prefetchCandidates(from: pool, excluding: []).count == 3)
        #expect(ShuffleEngine.prefetchCandidates(from: pool, excluding: [], limit: 5).count == 5)
    }

    @Test func aSmallPoolYieldsEverythingEligible() {
        let pool = ["a", "b"].map(entry)
        #expect(ShuffleEngine.prefetchCandidates(from: pool, excluding: []).count == 2)
    }

    @Test func anEntirelyRecentPoolYieldsNothing() {
        let pool = ["a", "b"].map(entry)
        #expect(ShuffleEngine.prefetchCandidates(from: pool, excluding: ["a", "b"]).isEmpty)
    }

    @Test func anEmptyPoolYieldsNothing() {
        #expect(ShuffleEngine.prefetchCandidates(from: [], excluding: ["a"]).isEmpty)
    }

    @Test func everyCandidateComesFromThePool() {
        let pool = (1...10).map { entry("asset-\($0)") }
        let ids = Set(pool.map(\.id))
        for candidate in ShuffleEngine.prefetchCandidates(from: pool, excluding: ["asset-1"]) {
            #expect(ids.contains(candidate.id))
        }
    }
}
