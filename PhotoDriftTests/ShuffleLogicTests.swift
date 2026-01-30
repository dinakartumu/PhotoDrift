import Testing
@testable import PhotoDrift

struct ShuffleLogicTests {
    private func makeEntry(id: String) -> UnifiedPool.PoolEntry {
        UnifiedPool.PoolEntry(id: id, sourceType: .applePhotos, albumID: "album1")
    }

    @Test func emptyPoolReturnsNil() {
        var selection = ShuffleSelection()
        let result = selection.select(from: [])
        #expect(result == nil)
    }

    @Test func singleItemPoolReturnsThatItem() {
        var selection = ShuffleSelection()
        let pool = [makeEntry(id: "only")]
        let result = selection.select(from: pool)
        #expect(result?.id == "only")
    }

    @Test func historyExcludesRecentlyUsedIDs() {
        var selection = ShuffleSelection(maxHistorySize: 10)
        let pool = [makeEntry(id: "a"), makeEntry(id: "b")]

        selection.addToHistory("a")
        // With "a" in history, selecting from pool should return "b"
        // (since "a" is excluded and "b" is the only candidate)
        let result = selection.select(from: pool)
        #expect(result?.id == "b")
    }

    @Test func historyAtMaxSizeRollsOffOldest() {
        var selection = ShuffleSelection(maxHistorySize: 3)
        selection.addToHistory("a")
        selection.addToHistory("b")
        selection.addToHistory("c")
        #expect(selection.recentHistory.count == 3)

        selection.addToHistory("d")
        #expect(selection.recentHistory.count == 3)
        #expect(selection.recentHistory == ["b", "c", "d"])
    }

    @Test func allItemsInHistoryFallsBackToFullPool() {
        var selection = ShuffleSelection(maxHistorySize: 10)
        let pool = [makeEntry(id: "a"), makeEntry(id: "b")]
        selection.addToHistory("a")
        selection.addToHistory("b")

        // All IDs are in history — should fall back to full pool (not return nil)
        let result = selection.select(from: pool)
        #expect(result != nil)
        #expect(result?.id == "a" || result?.id == "b")
    }

    @Test func addToHistoryBeyondMaxMaintainsMaxSize() {
        var selection = ShuffleSelection(maxHistorySize: 5)
        for i in 0..<20 {
            selection.addToHistory("item-\(i)")
        }
        #expect(selection.recentHistory.count == 5)
        #expect(selection.recentHistory == ["item-15", "item-16", "item-17", "item-18", "item-19"])
    }
}
