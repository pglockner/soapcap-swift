import Foundation

/// One stretch of transcribed speech. `speaker` is which AUDIO SOURCE picked
/// it up (microphone or system audio), not a voiceprint.
public struct Segment: Equatable, Sendable {
    public var speaker: String
    public var start: Double
    public var end: Double
    public var id: Int
    public var text: String

    public init(speaker: String = "Speaker", start: Double = 0, end: Double? = nil, id: Int = 0, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = end ?? start
        self.id = id
        self.text = text
    }
}

/// Reads the JSON `yap` writes: `{"segments": [{speaker, start, end, id, text}]}`,
/// every field optional (a single-track transcription has no speaker).
extension Segment: Decodable {
    private enum Key: String, CodingKey { case speaker, start, end, id, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self.init(speaker: try c.decodeIfPresent(String.self, forKey: .speaker) ?? "Speaker",
                  start: try c.decodeIfPresent(Double.self, forKey: .start) ?? 0,
                  end: try c.decodeIfPresent(Double.self, forKey: .end),
                  id: try c.decodeIfPresent(Int.self, forKey: .id) ?? 0,
                  text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
    }

    public static func decode(yapJSON data: Data) throws -> [Segment] {
        struct Document: Decodable { var segments: [Segment]? }
        return try JSONDecoder().decode(Document.self, from: data).segments ?? []
    }
}
