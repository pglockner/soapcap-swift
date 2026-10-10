import CoreMedia
import SoapcapCore
import Speech
import XCTest
@testable import SoapcapCapture

final class SegmenterTests: XCTestCase {
    /// Builds what a transcriber emits: runs of text, each with its time range.
    private func timed(_ runs: [(String, Double, Double)]) -> AttributedString {
        var out = AttributedString()
        for (text, start, end) in runs {
            var run = AttributedString(text)
            run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 1000),
                end: CMTime(seconds: end, preferredTimescale: 1000))
            out += run
        }
        return out
    }

    func testOneShortSentenceIsOneSegment() {
        let s = Segmenter.segments(in: timed([("Hello", 0.5, 0.9), (" there.", 0.9, 1.4)]), speaker: "Client")
        XCTAssertEqual(s, [Segment(speaker: "Client", start: 0.5, end: 1.4, id: 1, text: "Hello there.")])
    }

    func testSentencesBecomeSeparateSegments() {
        let s = Segmenter.segments(in: timed([("How are you?", 0, 1), (" I am fine.", 1.2, 2)]), speaker: "A")
        XCTAssertEqual(s.map(\.text), ["How are you?", "I am fine."])
        XCTAssertEqual(s.map(\.start), [0, 1.2])
        XCTAssertEqual(s.map(\.id), [1, 2])
    }

    func testALongPauseSplitsMidSentence() {
        let s = Segmenter.segments(in: timed([("well", 0, 0.4), (" anyway", 3, 3.5)]), speaker: "A")
        XCTAssertEqual(s.map(\.text), ["well", "anyway"])
        XCTAssertEqual(s.map(\.end), [0.4, 3.5])
    }

    func testAPauseAtTheThresholdDoesNotSplit() {
        let s = Segmenter.segments(in: timed([("well", 0, 0.5), (" anyway", 2.0, 2.5)]), speaker: "A")
        XCTAssertEqual(s.map(\.text), ["well anyway"])
    }

    /// The limit counts a piece's characters before each word is added, not the
    /// space that joins them, so a piece can run a few characters over (as yap's do).
    func testALongSentenceBreaksAtWordsNearTheLimit() {
        let words = ["I", " wanted", " to", " talk", " about", " what", " happened", " at", " work", " last", " week."]
        let runs = words.enumerated().map { ($0.element, Double($0.offset) * 0.3, Double($0.offset) * 0.3 + 0.25) }
        let s = Segmenter.segments(in: timed(runs), speaker: "A")
        XCTAssertGreaterThan(s.count, 1)
        XCTAssertTrue(s.allSatisfy { $0.text.count <= Segmenter.maxLength + 8 })
        XCTAssertEqual(s.map(\.text).joined(separator: " "), words.joined())
        XCTAssertEqual(s.first?.start, 0)
        XCTAssertEqual(s.last?.end, 3.25)
    }

    func testUntimedAndBlankTextIsDropped() {
        var text = timed([("  ", 0, 0.1)])
        text += AttributedString("no time range.")
        XCTAssertEqual(Segmenter.segments(in: text, speaker: "A"), [])
    }

    func testNumberingContinuesFromFirstID() {
        let s = Segmenter.segments(in: timed([("One.", 0, 1), (" Two.", 1, 2)]), speaker: "A", firstID: 7)
        XCTAssertEqual(s.map(\.id), [7, 8])
    }
}
