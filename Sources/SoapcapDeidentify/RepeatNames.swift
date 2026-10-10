import Foundation

public enum RepeatNames {
    /// A name tagged once is replaced everywhere it appears as a whole word.
    /// The model misses an occasional repeat ("the Sam dinner"), and one
    /// missed mention undoes the rest.
    public static func spans(in text: String, found: [Span]) -> [Span] {
        let names = Set(found.filter { $0.label == "FIRST_NAME" || $0.label == "LAST_NAME" }.map { text[$0.range] })
        var labelFor: [Substring: String] = [:]
        var order: [Substring] = []
        for span in found where names.contains(text[span.range]) {
            if labelFor.updateValue(span.label, forKey: text[span.range]) == nil { order.append(text[span.range]) }
        }
        return order.flatMap { name -> [Span] in
            let pattern = #"(?<!\w)"# + NSRegularExpression.escapedPattern(for: String(name)) + #"(?!\w)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return Rules.matches(of: regex, in: text).map { Span($0, labelFor[name]!) }
        }
    }
}
