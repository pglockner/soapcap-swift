import SoapcapCore
import SoapcapNote
import XCTest
@testable import SoapcapUI

@MainActor
final class DraftRunTests: XCTestCase {
    private var drafter: FakeDrafter!

    override func setUp() async throws { drafter = FakeDrafter() }

    private func draft(_ run: DraftRun) -> Task<DraftedNote?, Error> {
        Task { try await run.draft(format: .soap, transcript: "Client: hello", minutes: 1, systemLabel: "Client") { _ in } }
    }

    func testMemoryIsShownWhileDraftingAndNotAfter() async throws {
        let run = DraftRun(drafting: drafter, memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: 30) })
        XCTAssertNil(run.memory)
        let drafting = draft(run)
        await waitFor("memory shown") { run.memory != nil }
        XCTAssertEqual(run.trail.last, run.memory)           // each reading joins the chart's trail
        XCTAssertEqual(run.memory?.usedPercent, 70)
        XCTAssertTrue(run.isRunning)
        let note = try await drafting.value
        XCTAssertEqual(note?.text.hasPrefix("SUBJECTIVE:"), true)
        XCTAssertNil(run.memory)
        XCTAssertFalse(run.isRunning)
    }

    func testStoppingEndsTheDraftAtOnceAndThenTheModelGoes() async throws {
        drafter.releaseDelay = 300_000_000
        let run = DraftRun(drafting: drafter, memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: 30) })
        let drafting = draft(run)
        await waitFor("drafting") { run.isRunning && run.memory != nil }
        let stopping = run.stop()
        XCTAssertFalse(run.isRunning)
        XCTAssertNil(run.memory)
        let note = try await drafting.value
        XCTAssertNil(note, "a stopped draft has no note")
        XCTAssertEqual(drafter.events, ["draft"])            // the model is still going
        await stopping.value
        XCTAssertEqual(drafter.events, ["draft", "released"])
        XCTAssertNil(run.memory)
    }

    func testADraftWaitsForAModelThatIsStillStopping() async throws {
        drafter.releaseDelay = 300_000_000
        let run = DraftRun(drafting: drafter, memory: { nil })
        let first = draft(run)
        await waitFor("drafting") { run.isRunning }
        run.stop()
        let second = draft(run)
        let stopped = try await first.value, drafted = try await second.value
        XCTAssertNil(stopped)
        XCTAssertNotNil(drafted)
        XCTAssertEqual(drafter.events, ["draft", "released", "draft"])
    }

    func testANewDraftEndsTheOneInFlightAndWaitsForItsModelToGo() async throws {
        drafter.releaseDelay = 200_000_000
        let run = DraftRun(drafting: drafter, memory: { nil })
        let first = draft(run)
        await waitFor("drafting") { run.isRunning }
        let second = draft(run)                              // a session's draft while a test of the model runs
        let ended = try await first.value, drafted = try await second.value
        XCTAssertNil(ended, "the first is over, as if stopped")
        XCTAssertNotNil(drafted)
        XCTAssertEqual(drafter.events, ["draft", "released", "draft"])
        XCTAssertFalse(run.isRunning)
    }

    func testAModelAskedToGoTwiceAtOnceIsReleasedOnceAndBothWait() async {
        drafter.releaseDelay = 200_000_000
        let run = DraftRun(drafting: drafter, memory: { nil })
        let first = run.stop(), second = run.stop()
        await first.value
        await second.value
        XCTAssertEqual(drafter.events, ["released"])
        XCTAssertEqual(drafter.releases, 1)
        await run.stop().value                               // a later ask is a new release
        XCTAssertEqual(drafter.releases, 2)
    }

    func testADraftThatFailsFreesTheModelBeforeSayingSo() async {
        drafter.error = NoteError.emptyNote
        let run = DraftRun(drafting: drafter, memory: { nil })
        do { _ = try await draft(run).value; XCTFail("drafted") } catch {
            XCTAssertEqual(error as? NoteError, .emptyNote)
        }
        XCTAssertEqual(drafter.events, ["draft", "released"])
        XCTAssertFalse(run.isRunning)
    }
}
