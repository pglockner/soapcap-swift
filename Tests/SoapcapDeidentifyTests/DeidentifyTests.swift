import XCTest
@testable import SoapcapDeidentify

private func span(_ text: String, _ piece: String, _ label: String, confidence: Double = 0.9) -> Span {
    Span(text.range(of: piece)!, label, confidence: confidence)
}

/// A detector that reports fixed pieces of whatever text it is given.
private struct ScriptedDetector: PIIDetector {
    var pieces: [(String, String)] = []
    var fails = false
    var seen: @Sendable (String) -> Void = { _ in }

    func spans(in text: String) async throws -> [Span] {
        seen(text)
        if fails { throw CocoaError(.fileNoSuchFile) }
        return pieces.compactMap { piece, label in text.range(of: piece).map { Span($0, label, confidence: 0.9) } }
    }
}

/// The same cases as soapcap's test/deidentify.py.
final class RulesTests: XCTestCase {
    private func found(_ text: String) -> [String] { Rules.spans(in: text).map { "\(text[$0.range])=\($0.label)" } }

    func testAMonthTakesItsDayAndLowercaseMayIsLeft() {
        XCTAssertEqual(found("born March 14th, I may go"), ["March 14th=DATE"])
    }

    func testLongNumbersArePhonesOrIDs() {
        XCTAssertEqual(found("call 555-0199 or 988"), ["555-0199=PHONE"])
        XCTAssertEqual(found("id 123-456789"), ["123-456789=ID_NUM"])
    }

    func testRangesHoldAfterAnEmDashAndAnEmoji() {
        let text = "fine — really 👍🏽 — until August 3rd, call 555-0199"
        XCTAssertEqual(found(text), ["August 3rd=DATE", "555-0199=PHONE"])
    }
}

final class RedactorTests: XCTestCase {
    func testTheSameTextGetsTheSameToken() {
        let text = "Ana met Ben. Ana left."
        let spans = [Span(text.range(of: "Ana")!, "FIRST_NAME"), span(text, "Ben", "FIRST_NAME"),
                     Span(text.range(of: "Ana", options: .backwards)!, "FIRST_NAME")]
        let (out, summary) = Redactor.redact(text, spans)
        XCTAssertEqual(out, "[FIRST_NAME_1] met [FIRST_NAME_2]. [FIRST_NAME_1] left.")
        XCTAssertEqual(summary, "3 identifying details replaced (first name)")
    }

    func testANestedSpanIsDropped() {
        let text = "my sister Camila has"
        let spans = [span(text, "Camila", "FIRST_NAME"), span(text, "ila", "FIRST_NAME", confidence: 0.99)]
        XCTAssertEqual(Redactor.redact(text, spans).text, "my sister [FIRST_NAME_1] has")
    }

    func testTheLongerSpanWinsAtTheSameStart() {
        let text = "call 555-0233 now"
        let spans = [span(text, "555-0233", "PHONE", confidence: 1), span(text, "555", "PHONE", confidence: 0.6)]
        XCTAssertEqual(Redactor.redact(text, spans.reversed()).text, "call [PHONE_1] now")
    }

    func testNothingFound() {
        XCTAssertEqual(Redactor.redact("hello", []).text, "hello")
        XCTAssertEqual(Redactor.redact("hello", []).summary, "no identifying details found")
    }

    func testTheSummaryCountsEachCategoryInOrderOfAppearance() {
        let text = "Ana, 555-0199, Ben"
        let spans = [span(text, "Ben", "FIRST_NAME"), span(text, "555-0199", "PHONE"), span(text, "Ana", "FIRST_NAME")]
        XCTAssertEqual(Redactor.redact(text, spans).summary, "3 identifying details replaced (first name, phone)")
    }
}

final class SpanFilterTests: XCTestCase {
    func testClockTimesAreLeftInTheText() {
        let text = "we met 3:00 to 3:50, call Ana"
        let usable = SpanFilter.usable([span(text, "3:00", "TIME"), span(text, "3:50", "TIME"), span(text, "Ana", "FIRST_NAME")], in: text)
        XCTAssertEqual(usable.map(\.label), ["FIRST_NAME"])
        XCTAssertEqual(Redactor.redact(text, usable).text, "we met 3:00 to 3:50, call [FIRST_NAME_1]")
    }

    func testDatesAreStillRedacted() {
        let text = "on 03/05 at noon"
        XCTAssertEqual(Redactor.redact(text, SpanFilter.usable([span(text, "03/05", "DATE")], in: text)).text, "on [DATE_1] at noon")
    }

    func testAOneCharacterSpanIsDropped() {
        let text = "I haven't seen Ana"
        XCTAssertEqual(SpanFilter.usable([span(text, "t", "FIRST_NAME"), span(text, "Ana", "FIRST_NAME")], in: text).count, 1)
    }

    func testASpanIsSplitAtALineBreak() {
        let text = "at 12 Elm\nStreet today"
        let pieces = SpanFilter.splitAtLineBreaks([span(text, "12 Elm\nStreet", "STREET_ADDRESS")], in: text)
        XCTAssertEqual(pieces.map { String(text[$0.range]) }, ["12 Elm", "Street"])
    }
}

final class RepeatNamesTests: XCTestCase {
    func testAMissedRepeatIsCaughtAsAWholeWord() {
        let text = "Sam called. The Sam dinner, not the Samuel one."
        let found = RepeatNames.spans(in: text, found: [Span(text.range(of: "Sam")!, "FIRST_NAME")])
        XCTAssertEqual(found.map { text.distance(from: text.startIndex, to: $0.range.lowerBound) }, [0, 16])
        XCTAssertEqual(Set(found.map { String(text[$0.range]) }), ["Sam"])
    }

    func testOtherCategoriesAreNotRepeated() {
        let text = "at noon, around noon"
        XCTAssertEqual(RepeatNames.spans(in: text, found: [span(text, "noon", "TIME")]), [])
    }

    func testANameWithPunctuationInItIsMatchedLiterally() {
        let text = "Ms. O'Neil-Reyes (again O'Neil-Reyes)"
        XCTAssertEqual(RepeatNames.spans(in: text, found: [span(text, "O'Neil-Reyes", "LAST_NAME")]).count, 2)
    }
}

/// The label handling soapcap's test/run.sh checks with stub helpers.
final class DeidentifierTests: XCTestCase {
    func testSpeakerLabelsAreNeverSentToTheDetectorOrReplaced() async throws {
        let seen = Seen()
        let detector = ScriptedDetector(pieces: [("Sarah", "FIRST_NAME"), ("Camila", "FIRST_NAME")]) { seen.text = $0 }
        let result = try await Deidentifier(detector: detector)
            .deidentify("Sarah: hi there, with Camila.\nClient: Sarah said so.", kind: .transcript)
        XCTAssertEqual(seen.text, "hi there, with Camila.\nSarah said so.")
        XCTAssertEqual(result.text, "Sarah: hi there, with [FIRST_NAME_1].\nClient: [FIRST_NAME_2] said so.")
        XCTAssertEqual(result.summary, "2 identifying details replaced (first name)")
    }

    func testInANoteTheTextBeforeAColonIsRedactedToo() async throws {
        let detector = ScriptedDetector(pieces: [("Camila", "FIRST_NAME")])
        let result = try await Deidentifier(detector: detector)
            .deidentify("PLAN:\nCamila will call on Friday: she agreed.", kind: .note)
        XCTAssertEqual(result.text, "PLAN:\n[FIRST_NAME_1] will call on Friday: she agreed.")
    }

    func testNothingFoundLeavesTheTextUnchanged() async throws {
        let result = try await Deidentifier(detector: ScriptedDetector()).deidentify("Therapist: How was your week", kind: .transcript)
        XCTAssertEqual(result, Deidentified(text: "Therapist: How was your week", summary: "no identifying details found"))
    }

    func testAFailingDetectorThrowsInsteadOfPassingTextThrough() async {
        do {
            _ = try await Deidentifier(detector: ScriptedDetector(fails: true)).deidentify("Therapist: Hi Sarah", kind: .transcript)
            XCTFail("expected a throw")
        } catch {}
    }

    func testRulesAndRepeatsAreAddedToWhatTheDetectorFinds() async throws {
        let detector = ScriptedDetector(pieces: [("Sam", "FIRST_NAME"), ("3:00", "TIME")])
        let result = try await Deidentifier(detector: detector)
            .deidentify("Client: Sam rang at 3:00 on March 4th from 555-0199.\nClient: The Sam thing — again.", kind: .transcript)
        XCTAssertEqual(result.text, "Client: [FIRST_NAME_1] rang at 3:00 on [DATE_1] from [PHONE_1].\nClient: The [FIRST_NAME_1] thing — again.")
    }

    func testTheNumberOfLinesNeverChanges() async throws {
        let text = "A: lives at 12 Elm\nB: Street, he said\n\nB: ok"
        let detector = ScriptedDetector(pieces: [("12 Elm\nStreet", "STREET_ADDRESS")])
        let result = try await Deidentifier(detector: detector).deidentify(text, kind: .transcript)
        XCTAssertEqual(result.text, "A: lives at [STREET_ADDRESS_1]\nB: [STREET_ADDRESS_2], he said\n\nB: ok")
    }

    func testEmptyTextSkipsTheDetector() async throws {
        let result = try await Deidentifier(detector: ScriptedDetector(fails: true)).deidentify("\n", kind: .note)
        XCTAssertEqual(result.text, "\n")
    }
}

private final class Seen: @unchecked Sendable { var text = "" }
