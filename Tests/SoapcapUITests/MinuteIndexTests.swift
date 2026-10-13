import XCTest
@testable import SoapcapUI

final class MinuteIndexTests: XCTestCase {
    /// Lines "a", "b", … that began at the given seconds.
    private func index(_ times: [Int], pauses: [SessionPause] = []) -> MinuteIndex? {
        let lines = times.indices.map { String(UnicodeScalar(UInt8(97 + $0 % 26))) }
        return MinuteIndex(text: lines.joined(separator: "\n"), times: times, pauses: pauses)
    }

    /// The blocks in words: "1: d e" for turns d and e where minute 1
    /// begins, "1…: f" for more of that minute after a pause, and
    /// "paused 75+30" for a pause at 1:15 that lasted half a minute.
    private func blocks(_ index: MinuteIndex?) -> [String] {
        (index?.blocks ?? []).map { block in
            if let pause = block.pause { return "paused \(pause.at)+\(pause.length)" }
            return "\(block.minute)\(block.startsMinute ? "" : "…"): " + block.lines.joined(separator: " ")
        }
    }

    /// Each mark as [minute, the minute of the block it leads to].
    private func marks(_ times: [Int], every step: Int) -> [[Int]] {
        guard let index = index(times) else { return [] }
        return index.marks(every: step).map { [$0.minute, index.blocks[$0.block].minute] }
    }

    func testLinesAreGatheredByTheMinuteTheyBeganIn() {
        XCTAssertEqual(blocks(index([3, 40, 59, 60, 190])), ["0: a b c", "1: d", "3: e"])
        XCTAssertEqual(index([3, 60, 190])?.blocks.map(\.id), [0, 1, 2])
    }

    func testThereIsNoIndexWithoutATimeForEveryLine() {
        XCTAssertNil(MinuteIndex(text: "a\nb", times: [3]))
        XCTAssertNil(MinuteIndex(text: "a\nb", times: []))
        XCTAssertNil(MinuteIndex(text: "", times: []))
    }

    func testALineOutOfOrderStaysWithTheMinuteBeforeIt() {
        XCTAssertEqual(blocks(index([70, 20, 130])), ["1: a b", "2: c"])
    }

    func testAMarkLeadsToWhatWasBeingSaidAsThatMinuteBegan() {
        // A line a minute, from 0:10 to 12:10.
        let times = (0...12).map { $0 * 60 + 10 }
        XCTAssertEqual(marks(times, every: 5), [[0, 0], [5, 5], [10, 10]])
        XCTAssertEqual(marks(times, every: 1).count, 13)
        // Nothing began in minutes 5 to 7: minute 5 is in what began in minute 4.
        XCTAssertEqual(marks([10, 250, 480, 610], every: 5), [[0, 0], [5, 4], [10, 10]])
    }

    func testMarksThatWouldLeadToTheSamePlaceAreLeftOut() {
        // One speaker from 19:40 until past 26:00.
        XCTAssertEqual(marks([5, 310, 620, 905, 1180, 1570, 1830], every: 5),
                       [[0, 0], [5, 5], [10, 10], [15, 15], [20, 19], [30, 30]])
        // A session that is all one line has nowhere to go.
        XCTAssertEqual(marks([0], every: 1), [[0, 0]])
    }

    func testAStartThatComesLateIsStillTheFirstMark() {
        XCTAssertEqual(marks([75, 130], every: 1), [[0, 1], [2, 2]])
    }

    func testAPauseStandsWhereItFellBetweenTheTurns() {
        // Turns at 0:50, 1:05, 1:20 and 2:10; a pause at 1:15 for half a minute.
        let half = SessionPause(at: 75, length: 30)
        XCTAssertEqual(blocks(index([50, 65, 80, 130], pauses: [half])), ["0: a", "1: b", "paused 75+30", "1…: c", "2: d"])
        // A turn that began in the very second of the pause was under way: it comes first.
        XCTAssertEqual(blocks(index([50, 75, 80], pauses: [half])), ["0: a", "1: b", "paused 75+30", "1…: c"])
        // Before anything was said, after everything, and the same pause given twice.
        XCTAssertEqual(blocks(index([50, 65], pauses: [SessionPause(at: 300), SessionPause(at: 10, length: 5), SessionPause(at: 300)])),
                       ["paused 10+5", "0: a", "1: b", "paused 300+0"])
    }

    func testAPauseHasAMarkOfItsOwnInItsPlace() throws {
        // A line a minute at ten past; pauses at 5:00 on the minute and at 7:45.
        let times = (0...12).map { $0 * 60 + 10 }
        let five = SessionPause(at: 300, length: 20), seven = SessionPause(at: 465, length: 90)
        let index = try XCTUnwrap(index(times, pauses: [seven, five]))
        // The pause at 5:00 came before anything was said in minute 5, so it
        // stands before that minute's mark, as it does in the transcript.
        XCTAssertEqual(index.marks(every: 5), [
            .init(minute: 0, block: 0), .init(minute: 5, block: 5, pause: five), .init(minute: 5, block: 6),
            .init(minute: 7, block: 9, pause: seven), .init(minute: 10, block: 12),
        ])
        XCTAssertNotNil(index.blocks[5].pause)
        XCTAssertNotNil(index.blocks[9].pause)
        // A pause is not a stretch of the session, so it is never one of the marks picked out.
        XCTAssertEqual(MinuteIndex.shown(index.marks(every: 5), visible: 7...10), [5])
    }

    func testAPauseSaysHowLongItLasted() {
        XCTAssertEqual(SessionPause(at: 760, length: 95).text, "Paused for 1 minute, 35 seconds")
        XCTAssertEqual(SessionPause(at: 760, length: 95).textWithTime, "Paused at 12:40 for 1 minute, 35 seconds")
        XCTAssertEqual(SessionPause(at: 760, length: 600).text, "Paused for 10 minutes")
        // One that Stop ended at once has no length to speak of.
        XCTAssertEqual(SessionPause(at: 760).text, "Paused")
        XCTAssertEqual(SessionPause(at: 760).textWithTime, "Paused at 12:40")
    }

    func testTheMarksOnScreenArePickedOut() throws {
        let marks = try XCTUnwrap(index((0...52).map { $0 * 60 + 10 })).marks(every: 5)
        XCTAssertEqual(MinuteIndex.shown(marks, visible: 0...1), [0])
        XCTAssertEqual(MinuteIndex.shown(marks, visible: 20...21), [20])
        XCTAssertEqual(MinuteIndex.shown(marks, visible: 19...20), [15, 20])
        // The end of the session can't be scrolled to the top, so the last
        // marks are picked out together.
        XCTAssertEqual(MinuteIndex.shown(marks, visible: 48...52), [45, 50])
    }
}
