import Foundation

/// A transcript cut into the minutes of its session, so that the minute can
/// stand beside the text and be gone to. A pause in the session has a place
/// of its own among them, where it fell.
struct MinuteIndex: Equatable {
    /// A stretch of the transcript: turns that began in one minute of the
    /// session, or a pause.
    struct Block: Equatable, Identifiable {
        /// Its place in the transcript, counted from 0.
        let id: Int
        let minute: Int
        /// A line for each turn a speaker took. A pause has none.
        var lines: [String] = []
        /// Set when the block is a pause.
        var pause: SessionPause?
        /// Whether this is where its minute begins. A pause in the middle of
        /// a minute leaves the rest of that minute in a block after it,
        /// which doesn't say the minute again.
        var startsMinute = false
    }

    /// Somewhere to go to: a minute, with the block being spoken as that
    /// minute begins, or a pause.
    struct Mark: Hashable {
        let minute: Int
        let block: Int
        /// Set on a mark for a pause.
        var pause: SessionPause?
    }

    /// How far apart the minute marks can be, in minutes, from the finest.
    static let steps = [1, 2, 5, 10, 15, 30]

    let blocks: [Block]

    /// Nil unless `times` (seconds, in order) has one entry for each line of
    /// `text`: without a time for every line there is nothing to index by.
    init?(text: String, times: [Int], pauses: [SessionPause] = []) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !times.isEmpty, lines.count == times.count else { return nil }
        var blocks: [Block] = []
        var waiting = Set(pauses).sorted { ($0.at, $0.length) < ($1.at, $1.length) }[...]
        // The minute of the last turn. A line out of order stays in it.
        var minute = -1
        for (line, time) in zip(lines, times) {
            // A pause comes after every turn that had begun by then.
            while let pause = waiting.first, pause.at < time {
                blocks.append(Block(id: blocks.count, minute: pause.at / 60, pause: pause))
                waiting.removeFirst()
            }
            let began = max(minute, time / 60, 0)
            if let last = blocks.indices.last, blocks[last].pause == nil, blocks[last].minute == began {
                blocks[last].lines.append(String(line))
            } else {
                blocks.append(Block(id: blocks.count, minute: began, lines: [String(line)], startsMinute: began != minute))
            }
            minute = began
        }
        for pause in waiting { blocks.append(Block(id: blocks.count, minute: pause.at / 60, pause: pause)) }
        self.blocks = blocks
    }

    /// A mark every `step` minutes and one for each pause, in the order the
    /// transcript has them. Where one block runs past several minute marks
    /// (one speaker going on for minutes), only the first of them is kept:
    /// the others would lead to the same place.
    func marks(every step: Int) -> [Mark] {
        let turns = blocks.filter { $0.pause == nil }
        guard let end = turns.last?.minute else { return [] }
        var marks: [Mark] = []
        for minute in stride(from: 0, through: end, by: step) {
            // What was being said as the minute began: the turns that began
            // in it, or else the last to have begun before it.
            let block = (turns.first { $0.minute == minute } ?? turns.last { $0.minute < minute } ?? turns[0]).id
            if marks.last?.block != block { marks.append(Mark(minute: minute, block: block)) }
        }
        marks += blocks.compactMap { block in block.pause.map { Mark(minute: $0.at / 60, block: block.id, pause: $0) } }
        return marks.sorted { $0.block < $1.block }
    }

    /// The transcript as plain text, laid out as the window has it: the
    /// minute on a line of its own where a minute begins, a blank line
    /// between turns, and a line for each pause.
    var plainText: String {
        blocks.map { block in
            if let pause = block.pause { return "[\(pause.text)]" }
            let turns = block.lines.joined(separator: "\n\n")
            return block.startsMinute ? "[\(SessionClock.text(block.minute * 60))]\n\(turns)" : turns
        }.joined(separator: "\n\n")
    }

    /// The minute marks whose stretch of the session is on screen, from the
    /// first and last blocks that are. A mark's stretch runs up to the next
    /// minute mark.
    static func shown(_ marks: [Mark], visible: ClosedRange<Int>) -> Set<Int> {
        let marks = marks.filter { $0.pause == nil }
        return Set(marks.indices.filter { i in
            let next = i + 1 < marks.count ? marks[i + 1].block : .max
            return marks[i].block <= visible.upperBound && next > visible.lowerBound
        }.map { marks[$0].minute })
    }
}
