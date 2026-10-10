import AVFoundation
import SoapcapCore
import Speech

/// One audio source transcribed as one speaker.
final class Track: @unchecked Sendable {
    let speaker: String
    private let source: AudioSource
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let onLive: @Sendable (LiveLine) -> Void
    private let input = AsyncStream.makeStream(of: AnalyzerInput.self)
    private let lock = NSLock()
    private var paused = false
    private var results: Task<[Segment], Never>?

    init(source: AudioSource, speaker: String, transcriber: SpeechTranscriber,
         onLive: @escaping @Sendable (LiveLine) -> Void) {
        self.source = source
        self.speaker = speaker
        self.transcriber = transcriber
        self.onLive = onLive
        analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    var module: any SpeechModule { transcriber }

    func start() async throws {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptureError.noAudioFormat
        }
        let continuation = input.continuation
        source.onProblem = { [speaker, onLive] problem in
            onLive(LiveLine(speaker: speaker, text: "[\(problem)]", isFinal: true))
        }
        try await source.start(format: format) { [weak self] buffer in
            guard let self, !self.isPaused else { return }
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        try await analyzer.start(inputSequence: input.stream)
        let transcriber = transcriber, speaker = speaker, onLive = onLive
        results = Task {
            var segments: [Segment] = []
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { onLive(LiveLine(speaker: speaker, text: text, isFinal: result.isFinal)) }
                    if result.isFinal {
                        segments += Segmenter.segments(in: result.text, speaker: speaker, firstID: segments.count + 1)
                    }
                }
            } catch {}
            return segments
        }
    }

    /// While paused, incoming audio is dropped, so the transcript's clock
    /// (which counts audio heard) stops too.
    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }

    /// Stops the source, lets the recognizer finish what it has, and returns every segment.
    func finish() async -> [Segment] {
        await source.stop()
        input.continuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        return await results?.value ?? []
    }
}
