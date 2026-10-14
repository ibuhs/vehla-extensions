import Foundation

/// Shuffle that is fair: every song plays once per round before any plays a second time, and the song that ended
/// one round can't be the first of the next.
struct LofiShuffleBag {
    private(set) var remaining: [Int]
    let count: Int

    init(count: Int, remaining: [Int] = []) {
        self.count = count
        self.remaining = remaining
    }

    /// Starts a round without `current` (already played). With `keepCurrentForLater`, `current` joins the second
    /// half of the round.
    mutating func refill(excluding current: Int, keepCurrentForLater: Bool = false) {
        var order = Array(0..<count).filter { $0 != current }.shuffled()
        if keepCurrentForLater, !order.isEmpty { order.insert(current, at: Int.random(in: max(1, order.count / 2)...order.count)) }
        remaining = order
    }

    /// The next song, starting a new round when this one is used up.
    mutating func next(after current: Int) -> Int {
        if remaining.isEmpty { refill(excluding: current, keepCurrentForLater: true) }
        return remaining.isEmpty ? current : remaining.removeFirst()
    }

    mutating func markPlayed(_ position: Int) { remaining.removeAll { $0 == position } }

    mutating func putBack(_ position: Int) { remaining.insert(position, at: 0) }

    mutating func reset(_ values: [Int]) { remaining = values }
}
