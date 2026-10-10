import AVFoundation

/// The parts of an audio engine the microphone source uses, so the restart
/// logic can be tested without a device.
protocol InputEngine: AnyObject {
    /// 0 when there is no usable input (no device, or no permission).
    var inputSampleRate: Double { get }
    /// Called when the input device changes; the engine has stopped by then.
    var onConfigurationChange: (() -> Void)? { get set }
    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func start() throws
    func stop()
}

/// The default input device. When it changes mid-session (AirPods connect or
/// drop), capture restarts on the new one and the transcript carries on.
final class MicrophoneSource: AudioSource {
    var onProblem: ((String) -> Void)?
    private let engine: InputEngine
    private let granted: () async -> Bool
    private var handler: ((AVAudioPCMBuffer) -> Void)?

    init(engine: InputEngine = SystemInputEngine(),
         granted: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }) {
        self.engine = engine
        self.granted = granted
    }

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard await granted() else { throw CaptureError.microphoneDenied }
        let converter = BufferConverter(to: format)
        handler = { buffer in if let converted = converter.convert(buffer) { onBuffer(converted) } }
        guard listen() else { throw CaptureError.microphoneDenied }
        engine.onConfigurationChange = { [weak self] in self?.deviceChanged() }
    }

    func stop() async {
        engine.onConfigurationChange = nil
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

    private func deviceChanged() {
        guard handler != nil else { return }
        engine.removeTap()
        if !listen() { onProblem?("microphone lost; reconnect it, or stop and start again") }
    }
}

final class SystemInputEngine: InputEngine {
    var onConfigurationChange: (() -> Void)?
    private let engine = AVAudioEngine()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.onConfigurationChange?() }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var inputSampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in handler(buffer) }
    }

    func removeTap() { engine.inputNode.removeTap(onBus: 0) }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }
}
