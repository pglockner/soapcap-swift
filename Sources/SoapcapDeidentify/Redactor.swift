import Foundation

public enum Redactor {
    public static let nothingFound = "no entities detected"

    /// The text with each span replaced by a numbered token, and a one-line
    /// summary. One token per (category, exact text), numbered by first
    /// appearance: two different people never collide, repeats of one person
    /// always match.
    public static func redact(_ text: String, _ spans: [Span]) -> (text: String, summary: String) {
        let spans = SpanFilter.removingOverlaps(spans)
        guard !spans.isEmpty else { return (text, nothingFound) }
        var tokens: [String: String] = [:]
        var perLabel: [String: Int] = [:]
        var counts: [(label: String, count: Int)] = []
        var out = ""
        var position = text.startIndex
        for span in spans {
            let key = span.label + "\u{0}" + text[span.range]
            if tokens[key] == nil {
                perLabel[span.label, default: 0] += 1
                tokens[key] = "[\(span.label)_\(perLabel[span.label]!)]"
            }
            if let i = counts.firstIndex(where: { $0.label == span.label }) { counts[i].count += 1 } else { counts.append((span.label, 1)) }
            out += text[position..<span.range.lowerBound] + tokens[key]!
            position = span.range.upperBound
        }
        out += text[position...]
        let summary = "redacted \(spans.count) span(s): " + counts.map { "\($0.label) x\($0.count)" }.joined(separator: ", ")
        return (out, summary)
    }
}
