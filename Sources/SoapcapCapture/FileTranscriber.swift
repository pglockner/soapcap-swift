import AVFoundation
import SoapcapCore
import Speech

/// Transcribes an audio file on-device into `Segment`s.
public enum FileTranscriber {
    public static func segments(of file: URL, speaker: String = "Speaker",
                                locale: Locale = Locale(identifier: Locale.current.identifier)) async throws -> [Segment] {
        let transcriber = try await Recognizer.transcriber(locale: locale, live: false)
        try await Recognizer.prepare([transcriber], locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputAudioFile: try AVAudioFile(forReading: file), finishAfterFile: true)
        var segments: [Segment] = []
        for try await result in transcriber.results {
            segments += Segmenter.segments(in: result.text, speaker: speaker, firstID: segments.count + 1)
        }
        return segments
    }
}
