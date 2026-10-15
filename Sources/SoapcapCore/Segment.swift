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
