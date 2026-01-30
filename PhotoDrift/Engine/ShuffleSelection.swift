import Foundation

struct ShuffleSelection: Sendable {
    private(set) var recentHistory: [String] = []
    let maxHistorySize: Int

    init(maxHistorySize: Int = 20) {
        self.maxHistorySize = maxHistorySize
    }

    mutating func select(from pool: [UnifiedPool.PoolEntry]) -> UnifiedPool.PoolEntry? {
        guard !pool.isEmpty else { return nil }
        let candidates = pool.filter { !recentHistory.contains($0.id) }
        let available = candidates.isEmpty ? pool : candidates
        return available.randomElement()
    }

    mutating func addToHistory(_ id: String) {
        recentHistory.append(id)
        if recentHistory.count > maxHistorySize {
            recentHistory.removeFirst()
        }
    }
}
