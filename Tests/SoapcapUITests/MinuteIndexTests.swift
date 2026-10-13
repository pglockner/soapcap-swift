import XCTest
@testable import SoapcapUI

final class MinuteIndexTests: XCTestCase {
    /// Lines "a", "b", … that began at the given seconds.
    private func index(_ times: [Int]) -> MinuteIndex? {
        let lines = times.indices.map { String(UnicodeScalar(UInt8(97 + $0 % 26))) }
        return MinuteIndex(text: lines.joined(separator: "\n"), times: times)
    }

    private func marks(_ times: [Int], every step: Int) -> [[Int]] {
        index(times)?.marks(every: step).map { [$0.minute, $0.block] } ?? []
    }

    func testLinesAreGatheredByTheMinuteTheyBeganIn() {
        XCTAssertEqual(index([3, 40, 59, 60, 190])?.blocks,
                       [.init(minute: 0, lines: ["a", "b", "c"]), .init(minute: 1, lines: ["d"]), .init(minute: 3, lines: ["e"])])
    }

    func testThereIsNoIndexWithoutATimeForEveryLine() {
        XCTAssertNil(MinuteIndex(text: "a\nb", times: [3]))
        XCTAssertNil(MinuteIndex(text: "a\nb", times: []))
        XCTAssertNil(MinuteIndex(text: "", times: []))
    }

    func testALineOutOfOrderStaysWithTheMinuteBeforeIt() {
        XCTAssertEqual(index([70, 20, 130])?.blocks, [.init(minute: 1, lines: ["a", "b"]), .init(minute: 2, lines: ["c"])])
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
