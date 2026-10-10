import Foundation

/// Two fixed rules for things the model misses or only partly covers.
public enum Rules {
    // Case-sensitive on purpose: lowercase "may"/"march" are ordinary words; a
    // capitalized sentence-initial "May" is the one known false positive.
    private static let month = try! NSRegularExpression(
        pattern: #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:\s+\d{1,2}(?:st|nd|rd|th)?)?\b"#)
    // Counts digits (7+) rather than matching a phone layout, because
    // speech-to-text groups digits inconsistently ("123-456789" for a spoken SSN).
    private static let longNumber = try! NSRegularExpression(
        pattern: #"(?<![\w-])(?=(?:-?\d){7})\d+(?:-\d+)*(?![\w-])"#)

    /// Month names (with a day, if one follows) as DATE; numbers of seven or
    /// more digits as PHONE when there are exactly 7 or 10, otherwise ID_NUM.
    public static func spans(in text: String) -> [Span] {
        let months = matches(of: month, in: text).map { Span($0, "DATE") }
        let numbers = matches(of: longNumber, in: text).map { range -> Span in
            let digits = text[range].filter(\.isNumber).count
            return Span(range, digits == 7 || digits == 10 ? "PHONE" : "ID_NUM")
        }
        return months + numbers
    }

    static func matches(of regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }
}
