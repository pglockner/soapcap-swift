import AVFoundation
import os
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
        try await deliversUntilStopped(SystemInputEngine())
    }

    /// With echo cancellation on, as on this Mac's speakers, starting must
    /// not itself read as a change of device: voice processing can change
    /// the microphone's channels as it starts, and each change restarts it.
    func testWithEchoCancellationItDeliversAndNothingReadsAsAChange() async throws {
        let engine = SystemInputEngine(cancelsEcho: true)
        let changes = OSAllocatedUnfairLock(initialState: 0)
        engine.onConfigurationChange = { changes.withLock { $0 += 1 } }
        try await deliversUntilStopped(engine, for: .seconds(2))
        XCTAssertEqual(changes.withLock { $0 }, 0, "starting it was taken for a device change")
    }

    /// Voice processing on its own, whatever is playing: mono buffers at the
    /// rate asked for, and none after stop.
    func testVoiceProcessingDeliversMonoBuffersUntilStopped() async throws {
        try XCTSkipIf(SystemInputEngine().inputSampleRate == 0, "no microphone is connected")
        let heard = OSAllocatedUnfairLock(initialState: (buffers: 0, formats: Set<String>()))
        let voice = try VoiceProcessedInput(sampleRate: 48000) { buffer in
            let format = "\(buffer.format.channelCount)ch \(Int(buffer.format.sampleRate))"
            heard.withLock { $0.buffers += 1; $0.formats.insert(format) }
        }
        let deadline = Date().addingTimeInterval(2)
        while heard.withLock({ $0.buffers }) < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        voice.stop()
        let atStop = heard.withLock { $0 }
        XCTAssertGreaterThanOrEqual(atStop.buffers, 3, "voice processing sent nothing")
        XCTAssertEqual(atStop.formats, ["1ch 48000"])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(heard.withLock { $0.buffers }, atStop.buffers, "buffers came after stop")
    }

    /// Starts `engine`, waits for at least three buffers and `minimum`, then
    /// stops it and checks that nothing comes after.
    private func deliversUntilStopped(_ engine: SystemInputEngine, for minimum: Duration = .zero) async throws {
        try XCTSkipIf(engine.inputSampleRate == 0, "no microphone is connected")
        let buffers = OSAllocatedUnfairLock(initialState: 0)
        engine.installTap { _ in buffers.withLock { $0 += 1 } }
        try engine.start()
        let started = ContinuousClock.now
        let deadline = Date().addingTimeInterval(2)
        while buffers.withLock({ $0 }) < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(until: started + minimum)
        engine.stop()
        let atStop = buffers.withLock { $0 }
        XCTAssertGreaterThanOrEqual(atStop, 3, "the microphone sent nothing")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(buffers.withLock { $0 }, atStop, "buffers came after stop")
        engine.removeTap()
    }
}
