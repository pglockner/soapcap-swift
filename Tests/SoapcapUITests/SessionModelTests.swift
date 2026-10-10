import SoapcapCapture
import SoapcapCore
import XCTest
@testable import SoapcapUI

/// Scripted capture: returns `segments` on stop and records what it was asked to do.
private final class FakeCapture: Capturing {
    let live: AsyncStream<LiveLine>
    private let continuation: AsyncStream<LiveLine>.Continuation
    var segments: [Segment]
    var startError: Error?
    var calls: [String] = []

    init(_ segments: [Segment] = [], startError: Error? = nil) {
        (live, continuation) = AsyncStream.makeStream(of: LiveLine.self)
        self.segments = segments
        self.startError = startError
    }

    func start(micLabel: String, systemLabel: String) async throws {
        calls.append("start")
        if let startError { throw startError }
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() async -> [Segment] { calls.append("stop"); continuation.finish(); return segments }
    func hear(_ line: LiveLine) { continuation.yield(line) }
}

private let hello = [Segment(speaker: "Therapist", start: 0, end: 1, id: 1, text: "hi Bob"),
                     Segment(speaker: "Client", start: 2, end: 3, id: 1, text: "hello")]

/// A stand-in for the `soapcap` CLI, selected with SOAPCAP_BIN, for the steps
/// the app still hands to it.
private let stubScript = #"""
#!/usr/bin/env bash
case "$1" in
  deidentify)
    sed 's/Bob/[FIRST_NAME_1]/g'
    echo "redacted 1 span(s): FIRST_NAME x1" >&2 ;;
  note)
    cat > /dev/null
    printf 'SUBJECTIVE:\nformat %s\nNote about Bob\n' "$3" ;;
  doctor)
    echo "ok    all good" ;;
esac
"""#

@MainActor
final class SessionModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soapcap-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appendingPathComponent("soapcap")
        try stubScript.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        setenv("SOAPCAP_BIN", stub.path, 1)
        setenv("SOAPCAP_DEIDENTIFY_BIN", stub.path, 1) // any executable: enables the toggle
    }

    override func tearDown() async throws {
        for k in ["SOAPCAP_BIN", "SOAPCAP_DEIDENTIFY_BIN"] { unsetenv(k) }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Polls (suspending, so the main run loop and timers keep running).
    private func waitFor(_ what: String, timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for \(what)", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func recording(_ capture: FakeCapture, now: @escaping () -> Date = Date.init) async -> SessionModel {
        let m = SessionModel(makeCapture: { capture }, now: now)
        m.start()
        await waitFor("recording") { m.phase == .recording }
        return m
    }

    // MARK: pure logic

    func testDeidentifyAvailabilityFollowsTheHelperBinary() {
        XCTAssertTrue(Runner.deidentifyAvailable)
        setenv("SOAPCAP_DEIDENTIFY_BIN", dir.appendingPathComponent("missing").path, 1)
        XCTAssertFalse(Runner.deidentifyAvailable)
    }

    func testPipeRunsTheCLIWithInputOnStdin() async {
        let r = await Runner.pipe(["deidentify"], input: "hi Bob")
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.out, "hi [FIRST_NAME_1]")
    }

    func testAnInProgressLineIsReplacedUntilItIsFinal() {
        let m = SessionModel(makeCapture: { FakeCapture() })
        m.heard(LiveLine(speaker: "Client", text: "I", isFinal: false))
        m.heard(LiveLine(speaker: "Therapist", text: "mm", isFinal: false))
        m.heard(LiveLine(speaker: "Client", text: "I slept", isFinal: false))
        m.heard(LiveLine(speaker: "Client", text: "I slept well.", isFinal: true))
        m.heard(LiveLine(speaker: "Client", text: "Then", isFinal: false))
        XCTAssertEqual(m.liveLines.map(\.text), ["I slept well.", "mm", "Then"])
    }

    func testTheLiveStripKeepsOnlyTheLastLines() {
        let m = SessionModel(makeCapture: { FakeCapture() })
        for i in 1...40 { m.heard(LiveLine(speaker: "Client", text: "line \(i)", isFinal: true)) }
        XCTAssertEqual(m.liveLines.count, SessionModel.liveLimit)
        XCTAssertEqual(m.liveLines.last?.text, "line 40")
    }

    // MARK: session flow

    func testStopRendersBothSidesInOrder() async {
        let capture = FakeCapture(hello)
        let m = await recording(capture)
        m.deidentify = false
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.transcript, "Therapist: hi Bob\nClient: hello")
        XCTAssertEqual(m.notice, "")
        XCTAssertEqual(capture.calls, ["start", "stop"])
    }

    func testLiveLinesReachTheStripWhileRecording() async {
        let capture = FakeCapture(hello)
        let m = await recording(capture)
        capture.hear(LiveLine(speaker: "Client", text: "hello", isFinal: true))
        await waitFor("live line") { m.liveLines.count == 1 }
    }

    func testPauseStopsTheClockAndResumeContinuesTheSameCapture() async {
        var clock = Date(timeIntervalSince1970: 0)
        let capture = FakeCapture(hello)
        let m = await recording(capture, now: { clock })
        clock += 10; m.tick()
        XCTAssertEqual(m.elapsed, 10)
        m.pause()
        XCTAssertEqual(m.phase, .paused)
        clock += 60; m.tick()
        XCTAssertEqual(m.elapsed, 10)
        m.resume()
        XCTAssertEqual(m.phase, .recording)
        clock += 5; m.tick()
        XCTAssertEqual(m.elapsed, 15)
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(capture.calls, ["start", "pause", "resume", "stop"])
    }

    func testStoppingWhilePausedFinishes() async {
        let capture = FakeCapture(hello)
        let m = await recording(capture)
        m.pause()
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(capture.calls, ["start", "pause", "stop"])
    }

    func testDeidentifyRunsOnTheTranscriptAndThenTheNote() async {
        let m = await recording(FakeCapture(hello))
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.transcript, "Therapist: hi [FIRST_NAME_1]\nClient: hello")
        XCTAssertEqual(m.notice, "transcript: redacted 1 span(s): FIRST_NAME x1")
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(m.note, "SUBJECTIVE:\nformat soap\nNote about [FIRST_NAME_1]")
        XCTAssertEqual(m.notice, "note: redacted 1 span(s): FIRST_NAME x1")
    }

    func testWithoutDeidentifyNothingIsRedacted() async {
        let m = await recording(FakeCapture(hello))
        m.deidentify = false
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertTrue(m.transcript.contains("Bob"))
        XCTAssertTrue(m.note.contains("Bob"))
    }

    func testHearingOnlyTheMicrophoneWarns() async {
        let m = await recording(FakeCapture([hello[0]]))
        m.deidentify = false
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertTrue(m.notice.contains("nothing from the other party"), m.notice)
    }

    func testACaptureThatCannotStartShowsWhy() async {
        let m = SessionModel(makeCapture: { FakeCapture(startError: CaptureError.microphoneDenied) })
        m.start()
        await waitFor("error") { if case .error = m.phase { true } else { false } }
        guard case .error(let message) = m.phase else { return }
        XCTAssertTrue(message.contains("Privacy & Security > Microphone"), message)
    }

    func testACaptureThatHeardNothingIsAnError() async {
        let m = await recording(FakeCapture([]))
        m.stop()
        await waitFor("error") { if case .error = m.phase { true } else { false } }
    }

    func testNewSessionDuringARecordingStopsCaptureAndStaysIdle() async {
        let capture = FakeCapture(hello)
        let m = await recording(capture)
        m.newSession()
        await waitFor("capture stopped") { capture.calls.contains("stop") }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(m.transcript, "")
    }

    func testCheckPermissionsShowsTheGatheredChecks() async {
        let found = [Check("Microphone", .ok, "fine"), Check("Call audio", .failed, "off")]
        let m = SessionModel(makeCapture: { FakeCapture() }, checks: { found })
        m.diagnose()
        await waitFor("checks") { m.phase == .checks(found) }
        m.newSession()
        XCTAssertEqual(m.phase, .idle)
    }

    func testRunnerChecksReportTheToolAndTheHelper() {
        XCTAssertEqual(Runner.checks.map(\.status), [.ok, .ok])
        setenv("SOAPCAP_BIN", dir.appendingPathComponent("missing").path, 1)
        setenv("SOAPCAP_DEIDENTIFY_BIN", dir.appendingPathComponent("missing").path, 1)
        XCTAssertEqual(Runner.checks.map(\.status), [.failed, .warning])
    }
}
