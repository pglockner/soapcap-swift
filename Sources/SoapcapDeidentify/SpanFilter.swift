import Foundation

public enum SpanFilter {
    /// Categories the model finds but that are never replaced. TIME: the
    /// session's own time is the therapist's to submit with the note, and the
    /// model can't tell it from any other clock time. Dates are still replaced.
    public static let kept: Set<String> = ["TIME"]

    /// The model's spans worth acting on: not a kept category, and longer
    /// than one character (a one-character span is a stray token, "haven't"
    /// becoming "haven'[NAME]", never a whole identifier).
    public static func usable(_ spans: [Span], in text: String) -> [Span] {
        spans.filter { !kept.contains($0.label) && text[$0.range].unicodeScalars.count > 1 }
    }

    /// Two overlapping replacements would corrupt the text, so keep the
    /// earliest span at each position, preferring longer then more confident,
    /// and drop anything that overlaps one already kept.
    public static func removingOverlaps(_ spans: [Span]) -> [Span] {
        let sorted = spans.enumerated().sorted { a, b in
            if a.element.range.lowerBound != b.element.range.lowerBound { return a.element.range.lowerBound < b.element.range.lowerBound }
            if a.element.range.upperBound != b.element.range.upperBound { return a.element.range.upperBound > b.element.range.upperBound }
            if a.element.confidence != b.element.confidence { return a.element.confidence > b.element.confidence }
            return a.offset < b.offset
        }
        var kept: [Span] = []
        for (_, span) in sorted {
            if let last = kept.last, span.range.lowerBound < last.range.upperBound { continue }
            kept.append(span)
        }
        return kept
    }

    /// A span is never allowed to swallow a line break: the caller pairs
    /// lines back up with their speaker labels by position.
    public static func splitAtLineBreaks(_ spans: [Span], in text: String) -> [Span] {
        spans.flatMap { span -> [Span] in
            guard text[span.range].contains("\n") else { return [span] }
            var pieces: [Span] = []
            var start = span.range.lowerBound
            while start < span.range.upperBound {
                let end = text[start..<span.range.upperBound].firstIndex(of: "\n") ?? span.range.upperBound
                if start < end { pieces.append(Span(start..<end, span.label, confidence: span.confidence)) }
                start = end < span.range.upperBound ? text.index(after: end) : end
            }
            return pieces
        }
    }
}
