import SoapcapCapture
import SoapcapCore
import SoapcapDeidentify
import SoapcapNote
import XCTest
@testable import SoapcapUI

@MainActor
final class SessionModelTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private var settings: SessionSettings!
    private var drafter: FakeDrafter!
    private var deidentifier: FakeDeidentifier!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soapcap-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaults = MemoryDefaults()
        settings = SessionSettings(defaults: defaults)
        drafter = FakeDrafter()
        deidentifier = FakeDeidentifier()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
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

    func testTheStepsFollowASessionAndTheTranscriptCanBeGoneBackTo() async {
        let m = await recording(FakeCapture(hello))
        XCTAssertEqual(m.stage, .record)
        XCTAssertFalse(m.canGo(to: .transcript))
        XCTAssertFalse(m.canCheck)                  // the checks would take the screen from the session
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.stage, .transcript)
        XCTAssertFalse(m.canGo(to: .note))          // nothing is drafted yet
        XCTAssertEqual(m.notice, "Transcript: 1 identifying detail replaced (first name)")
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(m.stage, .note)
        XCTAssertEqual(m.notice, "Note: 1 identifying detail replaced (first name)")

        m.go(to: .transcript)
        XCTAssertEqual(m.phase, .transcript)
        XCTAssertEqual(m.stage, .transcript)
        XCTAssertEqual(m.notice, "Transcript: 1 identifying detail replaced (first name)")
        XCTAssertFalse(m.note.isEmpty)              // the note is kept meanwhile
        m.go(to: .note)
        XCTAssertEqual(m.phase, .note)
        XCTAssertEqual(m.notice, "Note: 1 identifying detail replaced (first name)")
        m.go(to: .record)                           // a session can't be gone back into
        XCTAssertEqual(m.phase, .note)

        m.newSession()
        XCTAssertEqual(m.stage, .record)
        XCTAssertEqual(m.notice, "")
    }

    func testWhatHasNotBeenKeptIsKnownSoThatItCanBeGuarded() async {
        let m = await recording(FakeCapture(hello))
        XCTAssertFalse(m.hasUnkeptWork)             // nothing to lose yet
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertTrue(m.hasUnkeptWork)              // leaving now would lose the transcript
        XCTAssertFalse(m.hasUnkeptNote)
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertTrue(m.hasUnkeptNote)
        XCTAssertEqual(m.draftedFormat, "soap")

        // Back at the transcript, drafting again would replace it; and the
        // note is still a SOAP note whatever the picker is moved to.
        m.go(to: .transcript)
        m.format = "dap"
        XCTAssertTrue(m.hasUnkeptNote)
        XCTAssertEqual(m.draftedFormat, "soap")

        m.go(to: .note)
        m.keep()
        XCTAssertFalse(m.hasUnkeptNote)
        XCTAssertFalse(m.hasUnkeptWork)             // it is on the clipboard

        m.draft()                                   // a new draft is unkept again
        await waitFor("the second note") { m.phase == .note }
        XCTAssertTrue(m.hasUnkeptNote)
        XCTAssertEqual(m.draftedFormat, "dap")
    }

    func testADraftThatFailsDoesNotCostTheTranscript() async {
        let m = await recording(FakeCapture(hello))
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        let transcript = m.transcript
        drafter.error = NoteError.notReady("Can't reach Ollama at http://localhost:11434.")
        m.draft()
        await waitFor("the failure") { if case .error = m.phase { true } else { false } }
        m.back()
        XCTAssertEqual(m.phase, .transcript)
        XCTAssertEqual(m.transcript, transcript)
        XCTAssertEqual(m.notice, "Transcript: 1 identifying detail replaced (first name)")

        // The checks, opened from the transcript, come back to it too.
        m.diagnose()
        await waitFor("checks") { if case .checks = m.phase { true } else { false } }
        m.back()
        XCTAssertEqual(m.phase, .transcript)
        XCTAssertEqual(m.transcript, transcript)
    }

    func testDeidentifyRunsOnTheTranscriptAndThenTheNote() async {
        let m = await recording(FakeCapture(hello))
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(m.transcript, "Therapist: hi [FIRST_NAME_1]\nClient: hello")
        XCTAssertEqual(m.notice, "Transcript: 1 identifying detail replaced (first name)")
        m.draft()
        await waitFor("note") { m.phase == .note }
        XCTAssertEqual(m.note, "SUBJECTIVE:\nformat soap\nNote about [FIRST_NAME_1]")
        XCTAssertEqual(m.notice, "Note: 1 identifying detail replaced (first name)")
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

    func testALaunchWithoutPermissionsStartsOnTheSetupScreen() async {
        let needed = [Check("Microphone", .warning, "ask")]
        var fixer = SessionModel.Fixer()
        fixer.hasPermissions = { false }
        let first = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier,
                                 fixer: fixer, checks: { needed })
        first.setUpIfNeeded()
        await waitFor("setup") { first.phase == .checks(needed) }
        fixer.hasPermissions = { true }
        let later = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier,
                                 fixer: fixer, checks: { needed })
        later.setUpIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(later.phase, .idle)
    }

    func testTheSetupButtonsAskMacOSAndOpenTheRightPlace() async {
        final class Seen: @unchecked Sendable { var did: [String] = [] }
        let seen = Seen()
        var fixer = SessionModel.Fixer()
        fixer.open = { seen.did.append("open \($0.absoluteString)") }
        fixer.askForMicrophone = { seen.did.append("ask microphone") }
        fixer.askForCallAudio = { seen.did.append("ask call audio") }
        let after = [Check("Microphone", .ok, "granted")]
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier,
                             fixer: fixer, checks: { after })
        m.perform(.askForMicrophone)
        await waitFor("checked again") { m.phase == .checks(after) }     // the answer shows without another click
        m.newSession()
        m.perform(.askForCallAudio)
        await waitFor("checked once more") { m.phase == .checks(after) }  // and so does this one, with no reopening
        m.perform(.open(URL(string: "https://ollama.com")!))
        XCTAssertEqual(seen.did, ["ask microphone", "ask call audio", "open https://ollama.com"])
    }

    func testTheDeidentifyCheckFollowsTheModelFiles() {
        XCTAssertEqual(ModelSetup.check(isReady: true).status, .ok)
        XCTAssertEqual(ModelSetup.check(isReady: false).status, .warning)
        XCTAssertTrue(ModelSetup.check(isReady: false).detail.contains("Settings"))
    }

    func testAVeryShortMemoryAsksBeforeABonsaiDraft() async {
        defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
        var free = 30
        let m = SessionModel(makeCapture: { FakeCapture(hello) }, settings: settings, drafting: drafter, deidentifying: deidentifier,
                             memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: free, swapUsedBytes: 7 << 30, swapTotalBytes: 8 << 30) })
        m.start()
        await waitFor("recording") { m.phase == .recording }
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        m.draftIfRoom()
        XCTAssertTrue(m.memoryQuestion?.contains("About 4 GB") == true, m.memoryQuestion ?? "nil")
        XCTAssertEqual(m.phase, .transcript)                 // nothing started
        free = 41                                            // advice only: no question
        m.draftIfRoom()
        XCTAssertNil(m.memoryQuestion)
        await waitFor("note") { m.phase == .note }
    }

    func testStoppingADraftFreesTheModelAndGoesBackToTheTranscript() async {
        let m = SessionModel(makeCapture: { FakeCapture(hello) }, settings: settings, drafting: drafter, deidentifying: deidentifier)
        m.start()
        await waitFor("recording") { m.phase == .recording }
        m.stop()
        await waitFor("transcript") { m.phase == .transcript }
        drafter.releaseDelay = 300_000_000
        m.draft()
        await waitFor("drafting") { m.draftRun.isRunning }
        m.stopDraft()
        XCTAssertEqual(m.phase, .working("Stopping…"))       // not the transcript until the model has gone
        XCTAssertFalse(m.draftRun.isRunning)
        XCTAssertNil(m.draftRun.memory)
        await waitFor("transcript") { m.phase == .transcript }
        XCTAssertEqual(drafter.events, ["draft", "released"])
        try? await Task.sleep(nanoseconds: 300_000_000)      // the abandoned draft finishing changes nothing
        XCTAssertEqual(m.phase, .transcript)
        XCTAssertEqual(m.note, "")
        XCTAssertEqual(drafter.releases, 1)
        m.draft()                                            // and drafting again still works
        await waitFor("note") { m.phase == .note }
        m.draft()
        await waitFor("drafting again") { m.draftRun.isRunning }
        m.stopDraft()
        await waitFor("note again") { m.phase == .note }     // the earlier note is kept
        XCTAssertTrue(m.note.contains("format soap"))
    }

    func testClosingAppsIsAdvisedOnlyForBonsaiWhenMemoryIsShort() {
        let short = { MemoryStatus(totalBytes: 16 << 30, freePercent: 41) }
        let m = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier, memory: short)
        XCTAssertNil(m.memoryAdvice)                         // llama3.1:8b: Ollama loads it, not the app
        defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
        XCTAssertTrue(m.memoryAdvice?.contains("Close other apps") == true, m.memoryAdvice ?? "nil")
        let roomy = SessionModel(makeCapture: { FakeCapture() }, settings: settings, drafting: drafter, deidentifying: deidentifier,
                                 memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: 68) })
        XCTAssertNil(roomy.memoryAdvice)
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
