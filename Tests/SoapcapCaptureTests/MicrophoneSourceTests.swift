import AVFoundation
import XCTest
@testable import SoapcapCapture

private final class FakeEngine: InputEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var rate = 48000.0, fails = false, entries: [String] = []
    var onConfigurationChange: (() -> Void)?

    var inputSampleRate: Double {
        get { lock.withLock { rate } }
        set { lock.withLock { rate = newValue } }
    }
    var startFails: Bool {
        get { lock.withLock { fails } }
        set { lock.withLock { fails = newValue } }
    }
    var log: [String] {
        get { lock.withLock { entries } }
        set { lock.withLock { entries = newValue } }
    }
    private func note(_ entry: String) { lock.withLock { entries.append(entry) } }

    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void) { note("tap") }
    func removeTap() { note("untap") }
    func start() throws {
        if startFails { throw CaptureError.microphoneDenied }
        note("start")
    }
    func stop() { note("stop") }
}

private final class Problems: @unchecked Sendable {
    private let lock = NSLock()
    private var said: [String] = []
    var all: [String] { lock.withLock { said } }
    func add(_ problem: String) { lock.withLock { said.append(problem) } }
}

final class MicrophoneSourceTests: XCTestCase {
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    /// What one try at a new device does to the engine.
    private let retry = ["untap", "stop", "tap", "start"]

    /// A source that tries a new device at once, once more 10 ms later, and
    /// from then on every 10 ms.
    private func started(_ engine: FakeEngine, secondTry: Duration = .milliseconds(10)) async throws -> (MicrophoneSource, Problems) {
        let problems = Problems()
        let source = MicrophoneSource(engine: engine, granted: { true }, pauses: [.zero, secondTry], retryEvery: .milliseconds(10))
        source.onProblem = { problems.add($0) }
        try await source.start(format: format) { _ in }
        return (source, problems)
    }

    private func wait(for what: String, _ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    func testStartTapsTheInputAndStartsTheEngine() async throws {
        let engine = FakeEngine()
        let (source, _) = try await started(engine)
        XCTAssertEqual(engine.log, ["tap", "start"])
        await source.stop()
    }

    /// Without the permission it says so; with it but no microphone, it
    /// says to connect one rather than to turn the permission on.
    func testWithoutPermissionOrAnInputItRefusesToStartAndSaysWhich() async {
        let denied = MicrophoneSource(engine: FakeEngine(), granted: { false })
        do { try await denied.start(format: format) { _ in }; XCTFail("started") } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }
        let engine = FakeEngine()
        engine.inputSampleRate = 0
        let noInput = MicrophoneSource(engine: engine, granted: { true })
        do { try await noInput.start(format: format) { _ in }; XCTFail("started") } catch {
            XCTAssertEqual(error as? CaptureError, .noMicrophone)
        }
    }

    func testADeviceChangeRestartsOnTheNewInput() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.log = []
        engine.onConfigurationChange?()
        await wait(for: "the restart") { engine.log == retry }
        XCTAssertEqual(problems.all, [])
        await source.stop()
    }

    func testADeviceThatIsNotReadyAtOnceIsTriedAgainWithoutAWordSaid() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine, secondTry: .milliseconds(300))
        engine.startFails = true            // AirPods still going into their call mode
        engine.log = []
        engine.onConfigurationChange?()
        await wait(for: "the first try") { engine.log.contains("tap") }
        engine.startFails = false
        await wait(for: "a try that works") { engine.log.last == "start" }
        XCTAssertEqual(problems.all, [])
        await source.stop()
    }

    func testADeviceChangeToNothingReportsTheMicrophoneLostAndKeepsTryingUntilItIsBack() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.inputSampleRate = 0
        engine.onConfigurationChange?()
        await wait(for: "the loss to be reported") { problems.all == ["microphone lost; still trying to get it back"] }
        // Nothing announces the device coming back; the tries go on by themselves.
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(problems.all.count, 1)       // said once, however many tries fail
        engine.inputSampleRate = 44100
        await wait(for: "the microphone to come back") { problems.all.last == "microphone back" }
        XCTAssertEqual(Array(engine.log.suffix(2)), ["tap", "start"])
        await source.stop()
    }

    func testAnEngineThatWillNotRestartReportsTheMicrophoneLost() async throws {
        let engine = FakeEngine()
        let (source, problems) = try await started(engine)
        engine.startFails = true
        engine.onConfigurationChange?()
        await wait(for: "the loss to be reported") { problems.all.count == 1 }
        await source.stop()
    }

    func testAfterStopNothingIsTriedAnyMore() async throws {
        let engine = FakeEngine()
        let (source, _) = try await started(engine)
        let change = engine.onConfigurationChange
        engine.startFails = true
        change?()
        await wait(for: "tries to begin") { engine.log.contains("tap") }
        await source.stop()                         // in the middle of trying
        XCTAssertNil(engine.onConfigurationChange)
        engine.log = []
        change?()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(engine.log, [])
    }
}
