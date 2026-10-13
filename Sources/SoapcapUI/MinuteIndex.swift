import Foundation

/// A transcript cut into the minutes of its session, so that the minute can
/// stand beside the text and be gone to.
struct MinuteIndex: Equatable {
    /// The lines that began in one minute of the session.
    struct Block: Equatable, Identifiable {
        let minute: Int
        var text: String
        var id: Int { minute }
    }

    /// A minute to go to, and the block being spoken as that minute begins.
    struct Mark: Equatable {
        let minute: Int
        let block: Int
    }

    /// How far apart marks can be, in minutes, from the finest.
    static let steps = [1, 2, 5, 10, 15, 30]

    let blocks: [Block]

    /// Nil unless `times` (seconds, in order) has one entry for each line of
    /// `text`: without a time for every line there is nothing to index by.
    init?(text: String, times: [Int]) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !times.isEmpty, lines.count == times.count else { return nil }
        var blocks: [Block] = []
        for (line, time) in zip(lines, times) {
            let minute = max(0, time) / 60
            if let last = blocks.indices.last, blocks[last].minute >= minute {
                blocks[last].text += "\n" + line
            } else {
                blocks.append(Block(minute: minute, text: String(line)))
            }
        }
        self.blocks = blocks
    }

    /// A mark every `step` minutes. Where one block runs past several marks
    /// (one speaker going on for minutes), only the first of them is kept:
    /// the others would lead to the same place.
    func marks(every step: Int) -> [Mark] {
        guard let end = blocks.last?.minute else { return [] }
        var marks: [Mark] = []
        var at = 0
        for minute in stride(from: 0, through: end, by: step) {
            while at + 1 < blocks.count, blocks[at + 1].minute <= minute { at += 1 }
            if marks.last?.block != blocks[at].minute { marks.append(Mark(minute: minute, block: blocks[at].minute)) }
        }
        return marks
    }

    /// The marks whose stretch of the session is on screen, from the first
    /// and last blocks that are. A mark's stretch runs up to the next mark.
    static func shown(_ marks: [Mark], visible: ClosedRange<Int>) -> Set<Int> {
        Set(marks.indices.filter { i in
            let next = i + 1 < marks.count ? marks[i + 1].block : .max
            return marks[i].block <= visible.upperBound && next > visible.lowerBound
        }.map { marks[$0].minute })
    }
}
