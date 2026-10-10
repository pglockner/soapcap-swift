import AVFoundation
import XCTest
@testable import SoapcapCapture

private final class FakeEngine: InputEngine {
    var inputSampleRate = 48000.0
    var onConfigurationChange: (() -> Void)?
    var startFails = false
    var log: [String] = []

    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void) { log.append("tap") }
    func removeTap() { log.append("untap") }
    func start() throws {
        if startFails { throw CaptureError.microphoneDenied }
        log.append("start")
    }
    func stop() { log.append("stop") }
}

final class MicrophoneSourceTests: XCTestCase {
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    private func started(_ engine: FakeEngine) async throws -> (MicrophoneSource, () -> [String]) {
        var problems: [String] = []
        let source = MicrophoneSource(engine: engine, granted: { true })
        source.onProblem = { problems.append($0) }
        try await source.start(format: format) { _ in }
        return (source, { problems })
    }

    func testStartTapsTheInputAndStartsTheEngine() async throws {
        let engine = FakeEngine()
        _ = try await started(engine)
        XCTAssertEqual(engine.log, ["tap", "start"])
    }

    func testWithoutPermissionOrAnInputItRefusesToStart() async {
        let denied = MicrophoneSource(engine: FakeEngine(), granted: { false })
        do { try await denied.start(format: format) { _ in }; XCTFail("started") } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }
        let engine = FakeEngine()
        engine.inputSampleRate = 0
        let noInput = MicrophoneSource(engine: engine, granted: { true })
        do { try await noInput.start(format: format) { _ in }; XCTFail("started") } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }
    }

    func testADeviceChangeRestartsOnTheNewInput() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.log = []
        engine.onConfigurationChange?()
        XCTAssertEqual(engine.log, ["untap", "tap", "start"])
        XCTAssertEqual(problems(), [])
        _ = source
    }

    func testADeviceChangeToNothingReportsTheMicrophoneLostThenRecovers() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.inputSampleRate = 0
        engine.onConfigurationChange?()
        XCTAssertEqual(problems().count, 1)
        engine.inputSampleRate = 44100
        engine.log = []
        engine.onConfigurationChange?()
        XCTAssertEqual(engine.log, ["untap", "tap", "start"])
        XCTAssertEqual(problems().count, 1)
        _ = source
    }

    func testAnEngineThatWillNotRestartReportsTheMicrophoneLost() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.startFails = true
        engine.onConfigurationChange?()
        XCTAssertEqual(problems().count, 1)
        _ = source
    }

    func testAfterStopADeviceChangeDoesNothing() async throws {
        let engine = FakeEngine()
        let (source, _) = try await started(engine)
        let change = engine.onConfigurationChange
        await source.stop()
        XCTAssertNil(engine.onConfigurationChange)
        engine.log = []
        change?()
        XCTAssertEqual(engine.log, [])
    }
}
