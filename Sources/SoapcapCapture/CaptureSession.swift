import Foundation
import SoapcapCore
import Speech

/// Text as it is being heard: `isFinal` false is the recognizer's current
/// guess for a stretch of speech, replaced by later lines until one is final.
public struct LiveLine: Equatable, Sendable {
    public var speaker: String
    public var text: String
    public var isFinal: Bool

    public init(speaker: String, text: String, isFinal: Bool) {
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
    }
}

/// Captures the microphone and the Mac's audio output together and
/// transcribes both on-device. No audio is stored.
public final class CaptureSession: @unchecked Sendable {
    /// Lines as they are heard, from both sides, until `stop()`.
    public let live: AsyncStream<LiveLine>
    private let liveContinuation: AsyncStream<LiveLine>.Continuation
    private var tracks: [Track] = []

    public init() {
        (live, liveContinuation) = AsyncStream.makeStream(of: LiveLine.self)
    }

    public func start(micLabel: String = "Therapist", systemLabel: String = "Client",
                      locale: Locale = Locale(identifier: Locale.current.identifier)) async throws {
        let continuation = liveContinuation
        var made: [Track] = []
        for (source, label) in [(MicrophoneSource() as AudioSource, micLabel), (SystemAudioSource(), systemLabel)] {
            let transcriber = try await Recognizer.transcriber(locale: locale, live: true)
            made.append(Track(source: source, speaker: label, transcriber: transcriber) { continuation.yield($0) })
        }
        try await Recognizer.prepare(made.map(\.module), locale: locale)
        do {
            for track in made { try await track.start() }
        } catch {
            for track in made { _ = await track.finish() }
            throw error
        }
        tracks = made
    }

    public func pause() { for track in tracks { track.isPaused = true } }
    public func resume() { for track in tracks { track.isPaused = false } }

    /// Ends capture and returns both sides' segments, ready for `Transcript.render`.
    public func stop() async -> [Segment] {
        var segments: [Segment] = []
        for track in tracks { segments += await track.finish() }
        tracks = []
        liveContinuation.finish()
        return segments
    }
}
