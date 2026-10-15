import AVFoundation
import XCTest
@testable import SoapcapCapture

/// The call's tap and the microphone on this Mac's real devices: what
/// otherwise takes a session in the app to check. Run only when
/// SOAPCAP_AUDIO_TESTS is set, since they need the Microphone and System
/// Audio Recording permissions, and from a terminal those are the
/// terminal's: allow both for it once, in System Settings › Privacy &
/// Security. Nothing is recorded and nothing is heard.
final class AudioHardwareTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOAPCAP_AUDIO_TESTS"] != nil, "set SOAPCAP_AUDIO_TESTS to run")
    }

    /// The tone the app plays itself comes back through a tap of its own
    /// sound: the checks screen's Call audio line.
    func testTheTapHearsTheTone() async {
        let heard = await CallAudio.hearsItself()
        XCTAssertTrue(heard, "nothing came back: allow System Audio Recording for this terminal")
    }

    /// The default input delivers buffers until stopped. Without the
    /// permission macOS hands over silence, so this checks the plumbing,
    /// not that anyone was heard.
    func testTheMicrophoneDeliversBuffersUntilStopped() async throws {
        let engine = SystemInputEngine()
        try XCTSkipIf(engine.inputSampleRate == 0, "no microphone is connected")
        let lock = NSLock()
        var buffers = 0
        engine.installTap { _ in lock.withLock { buffers += 1 } }
        try engine.start()
        let deadline = Date().addingTimeInterval(2)
        while lock.withLock({ buffers }) < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        engine.stop()
        let atStop = lock.withLock { buffers }
        XCTAssertGreaterThanOrEqual(atStop, 3, "the microphone sent nothing")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(lock.withLock { buffers }, atStop, "buffers came after stop")
        engine.removeTap()
    }
}
