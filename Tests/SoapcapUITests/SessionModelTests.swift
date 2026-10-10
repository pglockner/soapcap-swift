import SoapcapCapture
import SoapcapCore
import SoapcapDeidentify
import SoapcapNote
import XCTest
@testable import SoapcapUI

/// Scripted capture: returns `segments` on stop and records what it was asked to do.
private final class FakeCapture: Capturing {
    let live: AsyncStream<LiveLine>
    private let continuation: AsyncStream<LiveLine>.Continuation
    var segments: [Segment]
    var startError: Error?
    var calls: [String] = []
    var started = (mic: "", system: "", locale: "")

    init(_ segments: [Segment] = [], startError: Error? = nil) {
        (live, continuation) = AsyncStream.makeStream(of: LiveLine.self)
        self.segments = segments
        self.startError = startError
    }

    func start(micLabel: String, systemLabel: String, locale: Locale) async throws {
        calls.append("start")
        started = (micLabel, systemLabel, locale.identifier)
        if let startError { throw startError }
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() async -> [Segment] { calls.append("stop"); continuation.finish(); return segments }
    func hear(_ line: LiveLine) { continuation.yield(line) }
}

/// Scripted drafting: returns a note naming the format, and records what it was asked.
@MainActor private final class FakeDrafter: Drafting {
    var warnings: [String] = []
    var error: Error?
    var asked: [(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String)] = []
    var releases = 0

    func draft(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String,
               progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> DraftedNote {
        asked.append((format, transcript, minutes, systemLabel))
        progress(DraftProgress(title: "Drafting…", tokens: 7))
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let error { throw error }
        return DraftedNote(text: "SUBJECTIVE:\nformat \(format.rawValue)\nNote about Bob", warnings: warnings)
    }

    func release() async { releases += 1 }
}

private let hello = [Segment(speaker: "Therapist", start: 0, end: 1, id: 1, text: "hi Bob"),
                     Segment(speaker: "Client", start: 2, end: 3, id: 1, text: "hello")]

/// Scripted de-identifying: replaces "Bob", and records what kind of text it was given.
@MainActor private final class FakeDeidentifier: Deidentifying {
    var isReady = true
    var error: Error?
    var kinds: [LabeledText.Kind] = []

    func deidentify(_ text: String, kind: LabeledText.Kind) async throws -> Deidentified {
        kinds.append(kind)
        if let error { throw error }
        return Deidentified(text: text.replacingOccurrences(of: "Bob", with: "[FIRST_NAME_1]"), summary: "redacted 1 span(s): FIRST_NAME x1")
    }
}

@MainActor
final class SessionModelTests: XCTestCase {
    private var dir: URL!
    private var suite = ""
    private var settings: SessionSettings!
    private var drafter: FakeDrafter!
    private var deidentifier: FakeDeidentifier!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soapcap-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suite = "soapcap-tests-\(UUID().uuidString)"
        settings = SessionSettings(defaults: UserDefaults(suiteName: suite)!)
        drafter = FakeDrafter()
        deidentifier = FakeDeidentifier()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults().removePersistentDomain(forName: suite)
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
        let m = SessionModel(makeCapture: { capture }, now: now, settings: settings, drafting: drafter, deidentifying: deidentifier)
        m.start()
        await waitFor("recording") { m.phase == .recording }
        return m
    }

    // MARK: pure logic

    func testTheToggleIsOfferedOnceTheModelIsInstalled() {
        deidentifier.isReady = false
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier)
        XCTAssertFalse(m.canDeidentify)
        deidentifier.isReady = true
        m.refreshDeidentify()
        XCTAssertTrue(m.canDeidentify)
    }

    func testAnInProgressLineIsReplacedUntilItIsFinal() {
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier)
        m.heard(LiveLine(speaker: "Client", text: "I", isFinal: false))
        m.heard(LiveLine(speaker: "Therapist", text: "mm", isFinal: false))
        m.heard(LiveLine(speaker: "Client", text: "I slept", isFinal: false))
        m.heard(LiveLine(speaker: "Client", text: "I slept well.", isFinal: true))
        m.heard(LiveLine(speaker: "Client", text: "Then", isFinal: false))
        XCTAssertEqual(m.liveLines.map(\.text), ["I slept well.", "mm", "Then"])
    }

    func testTheLiveStripKeepsOnlyTheLastLines() {
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier)
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
        XCTAssertEqual(deidentifier.kinds, [.transcript, .note])
        XCTAssertEqual(m.warning, "")
    }

    func testAFailedDeidentifyKeepsTheTextAndWarnsThatItIsNotChecked() async {
        deidentifier.error = DeidentifyError.lineCountChanged
        let m = await recording(FakeCapture(hello))
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.transcript, "Therapist: hi Bob\nClient: hello")
        XCTAssertTrue(m.warning.hasPrefix("Not de-identified. This transcript still contains"), m.warning)
        XCTAssertFalse(m.notice.contains("redacted"))
        deidentifier.error = nil
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(m.warning, "")
        XCTAssertTrue(m.note.contains("[FIRST_NAME_1]"))
        deidentifier.error = DeidentifyError.lineCountChanged
        m.draft()
        await waitFor("note warning") { m.phase == .note && !m.warning.isEmpty }
        XCTAssertTrue(m.warning.hasPrefix("Not de-identified. This note still contains"), m.warning)
        XCTAssertTrue(m.note.contains("Bob"))
        m.newSession()
        XCTAssertEqual(m.warning, "")
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
        let m = SessionModel(makeCapture: { FakeCapture(startError: CaptureError.microphoneDenied) }, settings: settings, drafting: drafter, deidentifying: deidentifier)
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
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier, checks: { found })
        m.diagnose()
        await waitFor("checks") { m.phase == .checks(found) }
        m.newSession()
        XCTAssertEqual(m.phase, .idle)
    }

    func testTheDeidentifyCheckFollowsTheModelFiles() {
        XCTAssertEqual(ModelSetup.check(isReady: true).status, .ok)
        XCTAssertEqual(ModelSetup.check(isReady: false).status, .warning)
        XCTAssertTrue(ModelSetup.check(isReady: false).detail.contains("Settings"))
    }

    // MARK: settings

    func testSettingsDefaultToSoapcapsLabelsAndTheMacsLanguage() {
        XCTAssertEqual(settings.micLabel, "Therapist")
        XCTAssertEqual(settings.systemLabel, "Client")
        XCTAssertEqual(settings.locale.identifier, Locale.current.identifier)
        XCTAssertEqual(settings.format, "soap")
        XCTAssertTrue(settings.deidentify)
    }

    func testBlankOrColonLabelsFallBackToTheDefaults() {
        settings.defaults.set("   ", forKey: SessionSettings.Key.micLabel)
        settings.defaults.set("Cli: ent", forKey: SessionSettings.Key.systemLabel)
        XCTAssertEqual(settings.micLabel, "Therapist")
        XCTAssertEqual(settings.systemLabel, "Client")
    }

    func testChosenLabelsAndLanguageReachCaptureTheTranscriptAndTheNote() async {
        settings.defaults.set("Dr Lee", forKey: SessionSettings.Key.micLabel)
        settings.defaults.set("Patient", forKey: SessionSettings.Key.systemLabel)
        settings.defaults.set("en-GB", forKey: SessionSettings.Key.language)
        let capture = FakeCapture([Segment(speaker: "Dr Lee", start: 0, text: "hello"),
                                   Segment(speaker: "Patient", start: 1, text: "hi")])
        let m = await recording(capture)
        XCTAssertEqual(capture.started.mic, "Dr Lee")
        XCTAssertEqual(capture.started.system, "Patient")
        XCTAssertEqual(capture.started.locale, "en-GB")
        m.deidentify = false
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.transcript, "Dr Lee: hello\nPatient: hi")
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(drafter.asked.last?.systemLabel, "Patient")
        XCTAssertEqual(drafter.asked.last?.transcript, "Dr Lee: hello\nPatient: hi")
    }

    func testFormatAndDeidentifyAreRememberedForTheNextLaunch() {
        let first = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier)
        first.format = "dap"
        first.deidentify = false
        let second = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier)
        XCTAssertEqual(second.format, "dap")
        XCTAssertFalse(second.deidentify)
    }

    // MARK: drafting

    private func atTranscript(now: @escaping () -> Date = Date.init) async -> SessionModel {
        let m = await recording(FakeCapture(hello), now: now)
        m.deidentify = false
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        return m
    }

    func testDraftAsksForTheChosenFormatWithTheRecordedMinutes() async {
        var clock = Date(timeIntervalSince1970: 0)
        let m = await recording(FakeCapture(hello), now: { clock })
        m.deidentify = false
        clock += 125
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        m.format = "birp"
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(drafter.asked.last?.format, .birp)
        XCTAssertEqual(drafter.asked.last?.minutes, 2, "whole minutes, rounded down")
        XCTAssertEqual(m.note, "SUBJECTIVE:\nformat birp\nNote about Bob")
    }

    func testDraftingShowsProgressThenTheNotesWarnings() async {
        drafter.warnings = ["proofread it", "the Objective pass failed"]
        let m = await atTranscript()
        m.draft()
        await waitFor("progress") { m.phase == .working("Drafting…  7 tokens") }
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(m.notice, "proofread it\nthe Objective pass failed")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(m.phase, .note, "late progress must not replace the note")
    }

    func testAFailedDraftShowsWhy() async {
        drafter.error = NoteError.notReady("Can't reach Ollama at http://localhost:11434.")
        let m = await atTranscript()
        m.draft()
        await waitFor("error") { if case .error = m.phase { true } else { false } }
        guard case .error(let message) = m.phase else { return }
        XCTAssertTrue(message.contains("Can't reach Ollama"), message)
        XCTAssertEqual(drafter.releases, 1, "a failed draft must not leave the model loaded")
    }

    func testTheModelIsKeptBetweenDraftsAndReleasedWithTheSession() async {
        let m = await atTranscript()
        m.draft()
        await waitFor("note") { m.phase == .note }
        m.draft()
        await waitFor("second note") { self.drafter.asked.count == 2 && m.phase == .note }
        XCTAssertEqual(drafter.releases, 0)
        m.newSession()
        await waitFor("release") { self.drafter.releases == 1 }
    }

    func testNoteSettingsHaveSoapcapsDefaults() {
        XCTAssertEqual(settings.noteModel, "llama3.1:8b")
        XCTAssertEqual(settings.ollamaHost.absoluteString, "http://localhost:11434")
        XCTAssertEqual(settings.sessionType, "telehealth")
        settings.defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
        settings.defaults.set("not a url", forKey: SessionSettings.Key.ollamaHost)
        settings.defaults.set("in person", forKey: SessionSettings.Key.sessionType)
        XCTAssertEqual(settings.noteModel, "bonsai")
        XCTAssertEqual(settings.ollamaHost.absoluteString, "http://localhost:11434")
        XCTAssertEqual(settings.sessionType, "in person")
        settings.defaults.set("http://192.168.1.5:11434", forKey: SessionSettings.Key.ollamaHost)
        XCTAssertEqual(settings.ollamaHost.absoluteString, "http://192.168.1.5:11434")
    }
}
