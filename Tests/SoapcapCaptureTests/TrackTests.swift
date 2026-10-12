import AVFoundation
import Speech
import XCTest
@testable import SoapcapCapture

/// A source that can't start, as a microphone the app may not use.
private final class RefusedSource: AudioSource {
    var onProblem: ((String) -> Void)?
    var stopped = false
    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        throw CaptureError.microphoneDenied
    }
    func stop() async { stopped = true }
}

final class TrackTests: XCTestCase {
    /// A recording that can't start cleans up every track before it says
    /// why, so a track that never started has to finish all the same.
    func testATrackThatNeverStartedCanStillBeFinished() async throws {
        let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == "en-US" }
        try XCTSkipUnless(SpeechTranscriber.isAvailable && installed, "the en-US speech model isn't on this Mac")
        let transcriber = try await Recognizer.transcriber(locale: Locale(identifier: "en-US"), live: true)
        let source = RefusedSource()
        let track = Track(source: source, speaker: "Therapist", transcriber: transcriber) { _ in }
        do { try await track.start(); XCTFail("started") } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }

        let finished = expectation(description: "finish returns")
        Task {
            let segments = await track.finish()
            XCTAssertEqual(segments, [])
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertTrue(source.stopped)
    }
}
