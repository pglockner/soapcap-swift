import AVFoundation

/// Somewhere audio comes from. Buffers arrive already converted to `format`,
/// on whatever thread the source uses.
protocol AudioSource: AnyObject {
    /// Called with a short message if the source stops working mid-session,
    /// and again if it comes back.
    var onProblem: ((String) -> Void)? { get set }
    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws
    func stop() async
}

/// Converts buffers to one target format, rebuilding its converter when the
/// incoming format changes (a different microphone, a new stream).
final class BufferConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to target: AVAudioFormat) { self.target = target }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate).rounded(.up))
        guard capacity > 0, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}
