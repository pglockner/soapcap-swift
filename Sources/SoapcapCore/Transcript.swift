import Foundation

/// Turns segments into a readable, speaker-attributed transcript:
///
///     Therapist: How was the week?
///     Client: Rough. I barely slept.
public enum Transcript {
    /// One speaker's uninterrupted run of segments.
    public struct Turn: Equatable, Sendable {
        public var speaker: String
        public var text: String
        /// When the turn began, in seconds of the session heard.
        public var start: Double
    }

    /// Without headphones there's a one-directional leak: whatever plays
    /// through the speakers (the other party) is audible in the room, so the
    /// microphone hears it too and it is transcribed a second time under the
    /// mic label. The reverse doesn't happen. A mic-side segment whose wording
    /// is largely contained in a system-side segment nearby in time is that
    /// echo. Bias is toward NOT dropping when unsure: a missed echo is a
    /// harmless duplicate line, a wrongly dropped segment is lost content.
    public struct Dedupe: Equatable, Sendable {
        /// How far apart (s) two segments can be and still be "the same moment".
        public var window = 3.5
        /// Word-containment ratio (0-1) required to call it an echo.
        public var threshold = 0.7
        /// Segments with fewer words are never dropped: any single common
        /// word ("yeah", "so") trivially "contains" 1/1.
        public var minWords = 2

        public init() {}
    }

    /// `mic`/`system` are the two sources' speaker labels; leave them empty
    /// for single-track input, where there is nothing to compare against.
    public static func render(_ segments: [Segment], mic: String = "", system: String = "",
                              dedupe: Dedupe? = Dedupe()) -> String {
        render(turns(segments, mic: mic, system: system, dedupe: dedupe))
    }

    /// One line for each turn.
    public static func render(_ turns: [Turn]) -> String {
        turns.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    public static func turns(_ segments: [Segment], mic: String = "", system: String = "",
                             dedupe: Dedupe? = Dedupe()) -> [Turn] {
        var ordered = segments
            .map { s in var s = s; s.text = s.text.trimmingCharacters(in: .whitespacesAndNewlines); return s }
            // A segment with no word in it says nothing: the recognizer
            // sometimes hears a breath or a click as a lone full stop.
            .filter { $0.text.contains { $0.isLetter || $0.isNumber } }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        if let dedupe { ordered = removingEchoes(ordered, mic: mic, system: system, dedupe) }
        return ordered.reduce(into: [Turn]()) { turns, s in
            if let last = turns.indices.last, turns[last].speaker == s.speaker {
                turns[last].text += " " + s.text
            } else {
                turns.append(Turn(speaker: s.speaker, text: s.text, start: s.start))
            }
        }
    }

    public static func removingEchoes(_ segments: [Segment], mic: String, system: String,
                                      _ dedupe: Dedupe = Dedupe()) -> [Segment] {
        guard !mic.isEmpty, !system.isEmpty, mic != system else { return segments }
        let heard = segments.filter { $0.speaker == system }.map { ($0, words($0.text)) }
        return segments.filter { m in
            guard m.speaker == mic else { return true }
            let said = words(m.text)
            guard said.count >= dedupe.minWords else { return true }
            return !heard.contains { s, theirs in
                m.start - dedupe.window <= s.end && s.start <= m.end + dedupe.window
                    && containment(said, theirs) >= dedupe.threshold
            }
        }
    }

    /// A warning when the microphone was heard but the other side never was,
    /// as when the app can't hear what the Mac is playing; nil otherwise.
    public static func oneSidedNotice(_ segments: [Segment], mic: String, system: String) -> String? {
        guard segments.contains(where: { $0.speaker == mic }),
              !segments.contains(where: { $0.speaker == system }) else { return nil }
        return "Heard your side (\(mic)) but nothing from the other party (\(system)). "
            + "Use Check to see whether Soapcap can hear what the Mac is playing."
    }

    /// The distinct lowercased ASCII words of `text`.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init))
    }

    /// Fraction of the words shared by `a` and `b`, normalized by the SHORTER
    /// of the two, so a short fragment fully contained in a longer segment
    /// scores 1.0 however much longer the other is. Plain word overlap
    /// (Jaccard) would penalize that length mismatch and miss the 1-3 word
    /// trailing fragments an echo is chopped into.
    static func containment(_ a: Set<String>, _ b: Set<String>) -> Double {
        let shorter = min(a.count, b.count)
        return shorter == 0 ? 0 : Double(a.intersection(b).count) / Double(shorter)
    }
}
