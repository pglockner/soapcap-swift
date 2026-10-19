import AVFoundation
import SoapcapCore
import Speech
import XCTest
@testable import SoapcapCapture

final class ReadinessTests: XCTestCase {
    func testMicrophoneStatusMapsToACheck() {
        XCTAssertEqual(Readiness.microphone(.authorized).status, .ok)
        XCTAssertEqual(Readiness.microphone(.notDetermined).status, .warning)
        XCTAssertEqual(Readiness.microphone(.notDetermined).fix?.action, .askForMicrophone)
        let denied = Readiness.microphone(.denied)
        XCTAssertEqual(denied.status, .failed)
        XCTAssertEqual(denied.fix?.action, .open(Readiness.pane("Privacy_Microphone")))
        XCTAssertEqual(Readiness.microphone(.restricted).status, .failed)
    }

    func testCallAudioAsksFirstAndPointsAtSystemAudioAfterARefusal() {
        XCTAssertEqual(Readiness.callAudio(.allowed).status, .ok)
        let new = Readiness.callAudio(.notAsked)
        XCTAssertEqual(new.status, .warning)
        XCTAssertEqual(new.fix?.action, .askForCallAudio)
        let refused = Readiness.callAudio(.refused)
        XCTAssertEqual(refused.status, .failed)
        XCTAssertEqual(refused.fix?.action, .open(Readiness.callAudioPane))     // macOS won't ask a second time
        XCTAssertTrue(Readiness.callAudioPane.absoluteString.hasSuffix("Privacy_AudioCapture"))
    }

    func testCallAudioIsNotListenedForUntilMacOSHasBeenAsked() async throws {
        let defaults = MemoryDefaults()
        var listened = 0
        let hears = { listened += 1; return true }
        let before = await CallAudio.access(defaults: defaults, hears: hears)
        XCTAssertEqual(before, .notAsked)
        XCTAssertEqual(listened, 0)                 // listening is what makes macOS ask
        let answer = await CallAudio.ask(defaults: defaults, hears: hears)
        XCTAssertEqual(answer, .allowed)
        let refused = await CallAudio.access(defaults: defaults, hears: { false })
        XCTAssertEqual(refused, .refused)           // silence where the tone should be
    }

    /// Nothing connected is a warning of its own, not a missing permission,
    /// so the app still opens on the Ready screen.
    func testNoMicrophoneConnectedIsAWarningNotAPermission() {
        XCTAssertEqual(Readiness.input(connected: true), [])
        let missing = Readiness.input(connected: false)
        XCTAssertEqual(missing.map(\.status), [.warning])
        let checks = [Readiness.microphone(.authorized)] + missing
        XCTAssertFalse(checks.lackPermission)
        XCTAssertFalse(checks.needAttention)
    }

    func testAnUnsupportedLanguageFails() async {
        let checks = await Readiness.speech(locale: Locale(identifier: "tlh"))
        XCTAssertEqual(checks.map(\.status), [.failed])
    }

    /// Not on a Mac without on-device speech recognition at all, such as a
    /// CI runner, where the check rightly says it can't be done.
    func testEnglishIsRecognized() async throws {
        try XCTSkipUnless(SpeechTranscriber.isAvailable, "on-device speech recognition isn't available on this Mac")
        let checks = await Readiness.speech(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(checks.count, 1)
        XCTAssertNotEqual(checks[0].status, .failed)
    }
}
