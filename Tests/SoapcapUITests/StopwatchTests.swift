import XCTest
@testable import SoapcapUI

final class StopwatchTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testTheClockStandsStillWhilePausedAndKnowsHowLongThePauseWas() {
        var watch = Stopwatch()
        XCTAssertEqual(watch.seconds(at: at(5)), 0)                  // not started
        watch.run(at: at(0))
        XCTAssertEqual(watch.seconds(at: at(90)), 90)
        XCTAssertEqual(watch.pause(at: at(100)), 100)
        XCTAssertEqual(watch.seconds(at: at(400)), 100)              // still while paused
        XCTAssertEqual(watch.endPause(at: at(400)), 300)
        XCTAssertNil(watch.endPause(at: at(401)))                    // only once
        watch.run(at: at(400))
        XCTAssertEqual(watch.seconds(at: at(460)), 160)
        XCTAssertEqual(watch.halt(at: at(470)), 170)
        XCTAssertEqual(watch.seconds(at: at(9999)), 170)
    }

    func testStoppingWhilePausedCountsNothingMore() {
        var watch = Stopwatch()
        watch.run(at: at(0))
        _ = watch.pause(at: at(60))
        XCTAssertEqual(watch.endPause(at: at(120)), 60)
        XCTAssertEqual(watch.halt(at: at(120)), 60)
    }
}

final class ScreenNotesTests: XCTestCase {
    func testTheTranscriptAndTheNoteEachKeepTheirOwn() {
        var notes = ScreenNotes()
        notes.tell("Transcript: 2 details replaced")
        notes.warning = "Not de-identified."
        notes.tell("one side only")
        XCTAssertEqual(notes.notice, "Transcript: 2 details replaced\none side only")
        notes.put(.note)
        XCTAssertEqual(notes.notice, "")
        XCTAssertEqual(notes.warning, "")
        notes.tell("proofread it")
        notes.put(.note)                                              // already there: nothing changes
        XCTAssertEqual(notes.notice, "proofread it")
        notes.put(.transcript)
        XCTAssertEqual(notes.notice, "Transcript: 2 details replaced\none side only")
        XCTAssertEqual(notes.warning, "Not de-identified.")
        notes.put(.note)
        XCTAssertEqual(notes.notice, "proofread it")
    }
}
