import SoapcapCore
import SoapcapNote
import XCTest
@testable import SoapcapUI

@MainActor
final class ModelTestTests: XCTestCase {
    private let suite = "soapcap-model-test-\(UUID().uuidString)"
    private let whole = "9 minutes, telehealth\n\nSUBJECTIVE:\nSlept badly.\n\nOBJECTIVE:\nOn time via video.\n\nASSESSMENT:\nAnxious.\n\nPLAN:\nMeet again."
    private var drafter: FakeDrafter!
    private var run: DraftRun!
    private var settings: SessionSettings!

    override func setUp() async throws {
        drafter = FakeDrafter()
        drafter.text = whole
        run = DraftRun(drafting: drafter, memory: { nil })
        settings = SessionSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    override func tearDown() async throws { UserDefaults().removePersistentDomain(forName: suite) }

    /// A test whose clock moves 48 s between its two readings.
    private func modelTest(cautions: [String] = []) -> ModelTest {
        var times = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 48)]
        return ModelTest(run: run, settings: settings, cautions: { _, _ in cautions }, now: { times.count > 1 ? times.removeFirst() : times[0] })
    }

    func testAWholeNoteFromTheSampleSessionIsGoodAndTheModelIsLetGo() async throws {
        let test = modelTest()
        XCTAssertTrue(test.canStart)
        test.start()
        XCTAssertTrue(test.isRunning)
        XCTAssertFalse(test.canStart)
        await waitFor("a verdict") { !test.isRunning }
        XCTAssertEqual(test.state, .good(model: "llama3.1:8b", seconds: 48))
        XCTAssertEqual(test.note, whole)
        // The sample went to the model as a nine-minute SOAP session.
        XCTAssertEqual(drafter.asked.count, 1)
        XCTAssertEqual(drafter.asked.first?.format, .soap)
        XCTAssertEqual(drafter.asked.first?.minutes, 9)
        XCTAssertEqual(drafter.asked.first?.transcript, try SampleSession.transcript())
        await waitFor("the model to go") { drafter.events == ["draft", "released"] }
    }

    func testAnEmptySectionOrACautionIsAProblemAndTheNoteCanStillBeRead() async {
        drafter.text = whole.replacingOccurrences(of: "Anxious.", with: "Not addressed in this session.")
        drafter.warnings = ["The Objective pass failed — complete the Objective by hand."]
        let test = modelTest()
        test.start()
        await waitFor("a verdict") { !test.isRunning }
        XCTAssertEqual(test.state, .problem(model: "llama3.1:8b", reasons: [
            "ASSESSMENT is empty or \"Not addressed\"", "The Objective pass failed — complete the Objective by hand.",
        ]))
        XCTAssertNotNil(test.note)
    }

    func testWhatAModelsNotesAreAlwaysCautionedAboutIsNoProblem() async {
        UserDefaults(suiteName: suite)!.set("qwen3:8b", forKey: SessionSettings.Key.noteModel)
        drafter.warnings = ["qwen3:8b hasn't been tested"]
        let test = modelTest(cautions: ["qwen3:8b hasn't been tested"])
        test.start()
        await waitFor("a verdict") { !test.isRunning }
        XCTAssertEqual(test.state, .good(model: "qwen3:8b", seconds: 48))
    }

    func testAModelThatCannotDraftIsAProblemThatSaysWhy() async {
        drafter.error = NoteError.notReady("llama3.1:8b's model file isn't on this Mac. Get it in Settings (Cmd-comma).")
        let test = modelTest()
        test.start()
        await waitFor("a verdict") { !test.isRunning }
        XCTAssertEqual(test.state, .problem(model: "llama3.1:8b", reasons: ["llama3.1:8b's model file isn't on this Mac. Get it in Settings (Cmd-comma)."]))
        XCTAssertNil(test.note)
    }

    func testStoppingEndsItWithNoVerdictAndFreesTheModel() async {
        let test = modelTest()
        test.start()
        await waitFor("drafting") { run.isRunning }
        test.stop()
        XCTAssertEqual(test.state, .idle)
        await waitFor("the model to go") { drafter.events.last == "released" }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(test.state, .idle)       // the stopped run reports nothing afterwards
    }

    func testItDoesNotStartWhileASessionIsRecordedOrANoteIsDrafted() async throws {
        let test = modelTest()
        test.isBlocked = true
        test.start()
        XCTAssertEqual(test.state, .idle)
        test.isBlocked = false
        let drafting = Task { try await run.draft(format: .soap, transcript: "Client: hello", minutes: 1, systemLabel: "Client") { _ in } }
        await waitFor("a session's draft") { run.isRunning }
        XCTAssertFalse(test.canStart)
        test.start()
        XCTAssertEqual(test.state, .idle)
        _ = try await drafting.value
    }

    func testASessionsDraftTakesTheModelFromATest() async throws {
        let test = modelTest()
        test.start()
        await waitFor("the test to be drafting") { run.isRunning }
        let note = try await run.draft(format: .dap, transcript: "Client: hello", minutes: 1, systemLabel: "Client") { _ in }
        XCTAssertNotNil(note)                   // the session got its note
        XCTAssertEqual(test.state, .idle)       // and the test bowed out without a verdict
    }

    func testRecordingStopsATestAndBlocksAnother() async {
        let m = SessionModel(makeCapture: { FakeCapture(hello) }, settings: settings, drafting: drafter, deidentifying: FakeDeidentifier())
        m.modelTest.start()
        XCTAssertTrue(m.modelTest.isRunning)
        m.start()
        XCTAssertEqual(m.modelTest.state, .idle)
        await waitFor("recording") { m.phase == .recording }
        XCTAssertTrue(m.modelTest.isBlocked)
        m.stop()
        await waitFor("the transcript") { m.phase == .transcript }
        XCTAssertFalse(m.modelTest.isBlocked)
    }
}
