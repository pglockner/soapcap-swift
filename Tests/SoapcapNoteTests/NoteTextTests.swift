import XCTest
@testable import SoapcapNote

/// The same cases as soapcap's test/run.sh for the functions these port.
final class DraftCleanerTests: XCTestCase {
    func testAReEchoedTranscriptIsCutOff() {
        XCTAssertEqual(DraftCleaner.strippingTranscriptEcho("SUBJECTIVE:\nSome content.\n\nTRANSCRIPT:\nClient: this should never appear\n"),
                       "SUBJECTIVE:\nSome content.")
        XCTAssertEqual(DraftCleaner.strippingTranscriptEcho("SUBJECTIVE:\nNormal note, no echo.\n"),
                       "SUBJECTIVE:\nNormal note, no echo.")
    }

    func testTheFallbackIsStrippedOnlyWhenAppendedToARealObservation() {
        let fallback = "No observable presentation details available from a text-only transcript."
        XCTAssertEqual(DraftCleaner.strippingContaminatedFallback("The client appeared to be tearing up during the session. \(fallback)\n"),
                       "The client appeared to be tearing up during the session.")
        XCTAssertEqual(DraftCleaner.strippingContaminatedFallback(fallback + "\n"), fallback)
    }

    func testATrailingDisclaimerParagraphIsDropped() {
        XCTAssertEqual(DraftCleaner.strippingTrailingDisclaimer("PLAN:\nContinue weekly sessions.\n\nNote: this appears to be a test recording, not a real session.\n"),
                       "PLAN:\nContinue weekly sessions.")
        XCTAssertEqual(DraftCleaner.strippingTrailingDisclaimer("PLAN:\nContinue weekly sessions.\n\nPlease note - this is a test.\n\n"),
                       "PLAN:\nContinue weekly sessions.")
    }

    func testALegitimateSecondPlanParagraphIsKept() {
        let note = "PLAN:\nContinue weekly sessions.\n\nHomework: practice the breathing exercise daily."
        XCTAssertEqual(DraftCleaner.strippingTrailingDisclaimer(note + "\n"), note)
        XCTAssertEqual(DraftCleaner.strippingTrailingDisclaimer("Note: only paragraph."), "Note: only paragraph.")
    }

    func testAHollowPlanBecomesThePlanOfCareSentence() {
        XCTAssertEqual(DraftCleaner.defaultingPlan("A:\nx\n\nPLAN:\nNot addressed in this session.\n"),
                       "A:\nx\n\nPLAN:\nThe current plan of care will continue.")
        XCTAssertEqual(DraftCleaner.defaultingPlan("PLAN:\n\n"), "PLAN:\nThe current plan of care will continue.")
    }

    func testARealPlanAndOtherSectionsAreLeftAlone() {
        XCTAssertEqual(DraftCleaner.defaultingPlan("PLAN:\nWeekly sessions. Not addressed in this session.\n"),
                       "PLAN:\nWeekly sessions. Not addressed in this session.")
        XCTAssertEqual(DraftCleaner.defaultingPlan("ASSESSMENT:\nNot addressed in this session.\n\nPLAN:\nContinue.\n"),
                       "ASSESSMENT:\nNot addressed in this session.\n\nPLAN:\nContinue.")
    }

    func testCleanAppliesThePlanDefaultToSOAPOnly() {
        let draft = "DATA:\nx\n\nPLAN:\nNot addressed in this session.\n\nTRANSCRIPT:\nClient: hi"
        XCTAssertEqual(DraftCleaner.clean(draft, format: .dap), "DATA:\nx\n\nPLAN:\nNot addressed in this session.")
        XCTAssertEqual(DraftCleaner.clean(draft, format: .soap), "DATA:\nx\n\nPLAN:\nThe current plan of care will continue.")
    }
}

final class NoteFaultsTests: XCTestCase {
    func testFlagsANotAddressedSection() {
        let note = "SUBJECTIVE:\nSlept badly.\n\nOBJECTIVE:\nCalm.\n\nASSESSMENT:\nNot addressed in this session.\n\nPLAN:\nWeekly.\n"
        XCTAssertEqual(NoteFaults.faults(in: note, sections: ["SUBJECTIVE", "ASSESSMENT", "PLAN"]),
                       ["ASSESSMENT is empty or \"Not addressed\""])
    }

    func testTheNextSectionsTextDoesNotFillAnEmptyOneAndACutOffNoteIsFlagged() {
        let note = "SUBJECTIVE:\nNot addressed in this session.\n\nOBJECTIVE:\nCalm, cooperative.\n"
        XCTAssertEqual(NoteFaults.faults(in: note, sections: ["SUBJECTIVE", "ASSESSMENT"]),
                       ["SUBJECTIVE is empty or \"Not addressed\"", "no ASSESSMENT section"])
    }

    func testLenientCountsOnlyAMissingHeader() {
        let note = "SUBJECTIVE:\nNot addressed in this session.\n"
        XCTAssertEqual(NoteFaults.faults(in: note, sections: ["SUBJECTIVE", "PLAN"], lenient: true), ["no PLAN section"])
    }

    func testHeadersWithMarkupAndTextOnTheLineCount() {
        let note = "**SUBJECTIVE:** Felt anxious.\n\n## PLAN:\nWeekly."
        XCTAssertEqual(NoteFaults.faults(in: note, sections: ["SUBJECTIVE", "PLAN"]), [])
    }

    func testEachFormatNamesItsDraftSections() {
        XCTAssertEqual(NoteFormat.soap.draftSections, ["SUBJECTIVE", "ASSESSMENT", "PLAN"])
        XCTAssertEqual(NoteFormat.dap.draftSections, ["DATA", "ASSESSMENT", "PLAN"])
        XCTAssertEqual(NoteFormat.birp.draftSections, ["BEHAVIOR", "INTERVENTION", "RESPONSE", "PLAN"])
    }
}

final class ContextSizeTests: XCTestCase {
    private let short = String(repeating: "w ", count: 9000)
    private let long = String(repeating: "w ", count: 22000)

    func testCap() {
        XCTAssertFalse(ContextSize.exceedsCap(short, headroom: 1024))
        XCTAssertTrue(ContextSize.exceedsCap(long, headroom: 1024))
    }

    func testEstimate() {
        XCTAssertEqual(ContextSize.estimate("one two", headroom: 1024, floor: 4096), 4096)
        XCTAssertEqual(ContextSize.estimate(short, headroom: 2048), 16384)
        XCTAssertEqual(ContextSize.estimate(long, headroom: 2048), 32768)
    }
}

final class SessionLineTests: XCTestCase {
    func testSessionLine() {
        XCTAssertEqual(SessionLine.line(minutes: 63), "63 minutes, telehealth")
        XCTAssertEqual(SessionLine.line(minutes: 1), "1 minute, telehealth")
        XCTAssertEqual(SessionLine.line(minutes: 0), "under 1 minute, telehealth")
        XCTAssertEqual(SessionLine.adding(minutes: nil, to: "NOTE"), "NOTE")
        XCTAssertEqual(SessionLine.adding(minutes: 50, type: "in person", to: "NOTE"), "50 minutes, in person\n\nNOTE")
    }
}
