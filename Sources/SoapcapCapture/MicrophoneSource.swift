import AVFoundation
import CoreAudio

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
        // Allowed, so a microphone that won't start is missing or broken.
        guard listen() else { throw CaptureError.noMicrophone }
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
    /// does not give up. AirPods that connect mid-session can refuse the
    /// first try, made while they are still going into their call mode, and
    /// nothing says when they are ready. So the tries are spaced out.
    private func recover() async {
        var pauses = pauses[...]
        var lost = false
        while !Task.isCancelled, handler != nil {
            try? await Task.sleep(for: pauses.popFirst() ?? retryEvery)
            if Task.isCancelled || handler == nil { return }
            engine.removeTap()
            engine.stop()
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

/// The default input device, read straight from Core Audio, the way
/// `AudioTap` reads what the Mac plays. AVAudioEngine did this before: asked
/// about its input at the moment AirPods left, a new engine never answered,
/// and the session could not be stopped. Core Audio answers with an error.
final class SystemInputEngine: InputEngine {
    private let lock = NSLock()
    private let delivery = DispatchQueue(label: "soapcap.microphone.buffers")
    private let events = DispatchQueue(label: "soapcap.microphone.events")
    private var onChange: (() -> Void)?
    private var handler: ((AVAudioPCMBuffer) -> Void)?
    private var device = AudioDevice.none
    private var format: AVAudioFormat?
    private var proc: IOProc?
    /// One block for every listener, so that each can be taken off again.
    private var listener: AudioObjectPropertyListenerBlock?

    var onConfigurationChange: (() -> Void)? {
        get { lock.withLock { onChange } }
        set { lock.withLock { onChange = newValue } }
    }

    init() {
        listener = { [weak self] _, _ in self?.somethingChanged() }
        listen(to: kAudioHardwarePropertyDefaultInputDevice, of: AudioDevice.system, true)
    }

    deinit {
        stop()
        listen(to: kAudioHardwarePropertyDefaultInputDevice, of: AudioDevice.system, false)
    }

    var inputSampleRate: Double { AudioDevice.format(of: AudioDevice.default(.input), .input)?.sampleRate ?? 0 }

    func installTap(_ handler: @escaping (AVAudioPCMBuffer) -> Void) { lock.withLock { self.handler = handler } }
    func removeTap() { lock.withLock { handler = nil } }

    func start() throws {
        stop()
        let device = AudioDevice.default(.input)
        guard let handler = lock.withLock({ handler }), let format = AudioDevice.format(of: device, .input) else {
            throw CaptureError.noMicrophone
        }
        guard let proc = try? IOProc(device: device, queue: delivery, block: { _, input, _, output, _ in
            // A device that also plays is given silence to play.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            // The first buffer is the device's first input stream.
            guard input.pointee.mNumberBuffers > 0 else { return }
            var first = AudioBufferList(mNumberBuffers: 1, mBuffers: input.pointee.mBuffers)
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &first) { handler(buffer) }
        }) else { throw CaptureError.noMicrophone }
        lock.withLock { (self.device, self.format, self.proc) = (device, format, proc) }
        listen(to: kAudioDevicePropertyDeviceIsAlive, of: device, true)
        listen(to: kAudioDevicePropertyNominalSampleRate, of: device, true)
    }

    func stop() {
        let (device, proc) = lock.withLock {
            defer { (self.device, self.format, self.proc) = (AudioDevice.none, nil, nil) }
            return (self.device, self.proc)
        }
        guard let proc else { return }
        listen(to: kAudioDevicePropertyDeviceIsAlive, of: device, false)
        listen(to: kAudioDevicePropertyNominalSampleRate, of: device, false)
        proc.stop()
    }

    /// Passes a change on only if it means starting again: another device
    /// is the default input, or the one in use went away or changed its
    /// format. AirPods change their rate as they go into their call mode,
    /// which starting to listen causes; that alone must not start it again.
    private func somethingChanged() {
        let (device, format, onChange) = lock.withLock { (self.device, self.format, self.onChange) }
        if device != AudioDevice.none, AudioDevice.default(.input) == device, AudioDevice.format(of: device, .input) == format { return }
        onChange?()
    }

    private func listen(to selector: AudioObjectPropertySelector, of object: AudioObjectID, _ on: Bool) {
        guard let listener else { return }
        var address = AudioDevice.address(selector)
        if on {
            AudioObjectAddPropertyListenerBlock(object, &address, events, listener)
        } else {
            AudioObjectRemovePropertyListenerBlock(object, &address, events, listener)
        }
    }
}
