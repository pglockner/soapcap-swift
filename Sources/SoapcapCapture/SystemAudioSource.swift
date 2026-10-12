import AVFoundation

/// Whatever the Mac is playing (the other side of a call): a tap of every
/// app but this one. Sound only, so macOS asks about recording system
/// audio and never about the screen.
final class SystemAudioSource: AudioSource {
    var onProblem: ((String) -> Void)?
    private let tap = AudioTap()
    private let allowed: () async -> Bool

    /// `allowed` has macOS ask the first time. Without it a refusal would
    /// pass for a call where nobody spoke.
    init(allowed: @escaping () async -> Bool = { await CallAudio.ask() == .allowed }) {
        self.allowed = allowed
    }

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard await allowed() else { throw CaptureError.callAudioDenied }
        let converter = BufferConverter(to: format)
        try await tap.start(.everythingElse) { buffer in
            if let converted = converter.convert(buffer) { onBuffer(converted) }
        }
    }

    func stop() async { await tap.stop() }
}
