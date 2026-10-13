import Foundation

/// A transcript cut into the minutes of its session, so that the minute can
/// stand beside the text and be gone to.
struct MinuteIndex: Equatable {
    /// The lines that began in one minute of the session, a line for each
    /// turn a speaker took.
    struct Block: Equatable, Identifiable {
        let minute: Int
        var lines: [String]
        var id: Int { minute }
    }

    /// A minute to go to, and the block being spoken as that minute begins.
    struct Mark: Hashable {
        let minute: Int
        let block: Int
        /// Set on a mark for a pause in the session: the second it began.
        var pausedAt: Int?
    }

    /// How far apart marks can be, in minutes, from the finest.
    static let steps = [1, 2, 5, 10, 15, 30]

    let blocks: [Block]
    /// When the session was paused, in seconds, in order.
    let pauses: [Int]

    /// Nil unless `times` (seconds, in order) has one entry for each line of
    /// `text`: without a time for every line there is nothing to index by.
    init?(text: String, times: [Int], pauses: [Int] = []) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !times.isEmpty, lines.count == times.count else { return nil }
        var blocks: [Block] = []
        for (line, time) in zip(lines, times) {
            let minute = max(0, time) / 60
            if let last = blocks.indices.last, blocks[last].minute >= minute {
                blocks[last].lines.append(String(line))
            } else {
                blocks.append(Block(minute: minute, lines: [String(line)]))
            }
        }
        self.blocks = blocks
        self.pauses = Set(pauses).sorted()
    }

    /// A mark every `step` minutes, with a mark for each pause among them
    /// where it fell. Where one block runs past several minute marks (one
    /// speaker going on for minutes), only the first of them is kept: the
    /// others would lead to the same place.
    func marks(every step: Int) -> [Mark] {
        guard let end = blocks.last?.minute else { return [] }
        var marks: [Mark] = []
        for minute in stride(from: 0, through: end, by: step) {
            let block = block(at: minute)
            if marks.last?.block != block { marks.append(Mark(minute: minute, block: block)) }
        }
        marks += pauses.map { Mark(minute: $0 / 60, block: block(at: $0 / 60), pausedAt: $0) }
        // In the order they came; a pause on the minute comes after its mark.
        return marks.sorted { ($0.pausedAt ?? $0.minute * 60, $0.pausedAt == nil ? 0 : 1) < ($1.pausedAt ?? $1.minute * 60, $1.pausedAt == nil ? 0 : 1) }
    }

    /// The block being spoken as a minute begins: the last to have begun by
    /// then, or the first of all.
    private func block(at minute: Int) -> Int {
        (blocks.last { $0.minute <= minute } ?? blocks[0]).minute
    }

    /// The minute marks whose stretch of the session is on screen, from the
    /// first and last blocks that are. A mark's stretch runs up to the next
    /// minute mark.
    static func shown(_ marks: [Mark], visible: ClosedRange<Int>) -> Set<Int> {
        let marks = marks.filter { $0.pausedAt == nil }
        return Set(marks.indices.filter { i in
            let next = i + 1 < marks.count ? marks[i + 1].block : .max
            return marks[i].block <= visible.upperBound && next > visible.lowerBound
        }.map { marks[$0].minute })
    }
}
