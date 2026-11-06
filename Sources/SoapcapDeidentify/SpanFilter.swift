import Foundation

public enum SpanFilter {
    /// Categories the model finds but that are never replaced. TIME: the
    /// session's own time is the therapist's to submit with the note, and the
    /// model can't tell it from any other clock time. Dates are still replaced.
    public static let kept: Set<String> = ["TIME"]

    /// The model's spans worth acting on: not a kept category, and longer
    /// than one character (a one-character span is a stray token, "haven't"
    /// becoming "haven'[NAME]", never a whole identifier). A span that took
    /// in the sentence's full stop or comma ("Mary." in "It's Mary. Mary.")
    /// gives it back: replacing it would eat the punctuation, and a repeat
    /// of the name without it would go unnoticed.
    public static func usable(_ spans: [Span], in text: String) -> [Span] {
        spans.compactMap { span -> Span? in
            var end = span.range.upperBound
            while end > span.range.lowerBound, ".,;:!?".contains(text[text.index(before: end)]) {
                end = text.index(before: end)
            }
            let trimmed = Span(span.range.lowerBound..<end, span.label, confidence: span.confidence)
            return !kept.contains(span.label) && text[trimmed.range].unicodeScalars.count > 1 ? trimmed : nil
        }
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
