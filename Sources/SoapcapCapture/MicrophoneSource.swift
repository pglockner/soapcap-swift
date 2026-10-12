import AVFoundation

/// The parts of an audio engine the microphone source uses, so the restart
/// logic can be tested without a device.
protocol InputEngine: AnyObject {
    /// 0 when there is no usable input (no device, or no permission).
    var inputSampleRate: Double { get }
    /// Called when the input device changes; the engine has stopped by then.
    /// It may be called on any thread.
    var onConfigurationChange: (() -> Void)? { get set }
    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func start() throws
    func stop()
    /// Starts over with an engine that looks at the input device afresh.
    func renew()
}

/// The default input device. When it changes mid-session (AirPods connect or
/// drop), capture restarts on the new one and the transcript carries on.
final class MicrophoneSource: AudioSource {
    var onProblem: ((String) -> Void)?
    private let engine: InputEngine
    private let granted: () async -> Bool
    private let pauses: [Duration]
    private let retryEvery: Duration
    private var handler: ((AVAudioPCMBuffer) -> Void)?
    /// At most one change waits its turn: what matters is the device now.
    private let changes = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    private var watcher: Task<Void, Never>?

    /// `pauses` come before each of the first tries at a new device, and
    /// after them it is tried again every `retryEvery`.
    init(engine: InputEngine = SystemInputEngine(),
         granted: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
         pauses: [Duration] = [.zero, .milliseconds(500), .seconds(1), .seconds(2), .seconds(4)],
         retryEvery: Duration = .seconds(5)) {
        self.engine = engine
        self.granted = granted
        self.pauses = pauses
        self.retryEvery = retryEvery
    }

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard await granted() else { throw CaptureError.microphoneDenied }
        let converter = BufferConverter(to: format)
        handler = { buffer in if let converted = converter.convert(buffer) { onBuffer(converted) } }
        guard listen() else { throw CaptureError.microphoneDenied }
        engine.onConfigurationChange = { [changes] in changes.continuation.yield() }
        watcher = Task { [weak self, changes] in
            for await _ in changes.stream { await self?.recover() }
        }
    }

    func stop() async {
        engine.onConfigurationChange = nil
        watcher?.cancel()
        await watcher?.value
        watcher = nil
        handler = nil
        engine.removeTap()
        engine.stop()
    }

    /// Taps the current input device and starts the engine; false if it can't.
    private func listen() -> Bool {
        guard let handler, engine.inputSampleRate > 0 else { return false }
        engine.installTap(handler)
        do { try engine.start() } catch { engine.removeTap(); return false }
        return true
    }

    /// Gets the microphone going again after the input device changed, and
    /// does not give up. AirPods that connect mid-session refuse the first
    /// try, made while they are still going into their call mode, and
    /// nothing says when they are ready. So the tries are spaced out, and
    /// each is made with a new engine.
    private func recover() async {
        var pauses = pauses[...]
        var lost = false
        while !Task.isCancelled, handler != nil {
            try? await Task.sleep(for: pauses.popFirst() ?? retryEvery)
            if Task.isCancelled || handler == nil { return }
            engine.removeTap()
            engine.stop()
            engine.renew()
            if listen() {
                if lost { onProblem?("microphone back") }
                return
            }
            if pauses.isEmpty, !lost {
                lost = true
                onProblem?("microphone lost; still trying to get it back")
            }
        }
    }
}

final class SystemInputEngine: InputEngine {
    var onConfigurationChange: (() -> Void)?
    private var engine = AVAudioEngine()
    private var observer: NSObjectProtocol?

    init() { observe() }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// The engine posts this from a thread of its own, where it must not be
    /// called back; whoever listens has to act elsewhere.
    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.onConfigurationChange?() }
    }

    var inputSampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in handler(buffer) }
    }

    func removeTap() { engine.inputNode.removeTap(onBus: 0) }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }

    func renew() {
        engine = AVAudioEngine()
        observe()
    }
}
