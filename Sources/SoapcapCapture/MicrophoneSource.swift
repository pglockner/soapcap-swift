import AVFoundation

/// The default input device, through an AVAudioEngine tap.
final class MicrophoneSource: AudioSource {
    private let engine = AVAudioEngine()

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CaptureError.microphoneDenied }
        let input = engine.inputNode
        guard input.outputFormat(forBus: 0).sampleRate > 0 else { throw CaptureError.microphoneDenied }
        let converter = BufferConverter(to: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            if let converted = converter.convert(buffer) { onBuffer(converted) }
        }
        do { try engine.start() } catch { throw CaptureError.microphoneDenied }
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
