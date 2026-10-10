import Foundation

/// A transcript with its speaker labels set aside. A label is never sent to
/// the detector and never replaced, even if it happens to be a real name.
public struct LabeledText: Equatable, Sendable {
    public enum Kind: Sendable {
        /// "Label: words" lines; everything before a line's first ": " is the label.
        case transcript
        /// A drafted note has no speaker labels: every line is body, or
        /// whatever came before a line's first ": " would be skipped.
        case note
    }

    public let labels: [String?]
    /// The lines without their labels, joined by newlines.
    public let body: String

    public init(_ text: String, kind: Kind) {
        var labels: [String?] = []
        var bodies: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if kind == .transcript, let colon = line.range(of: ": ") {
                labels.append(String(line[..<colon.lowerBound]))
                bodies.append(line[colon.upperBound...])
            } else {
                labels.append(nil)
                bodies.append(line)
            }
        }
        self.labels = labels
        self.body = bodies.joined(separator: "\n")
    }

    /// The labels put back in front of `body`'s lines, or nil if `body` no
    /// longer has one line per label.
    public func rejoined(with body: String) -> String? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == labels.count else { return nil }
        return zip(labels, lines).map { label, line in label.map { "\($0): \(line)" } ?? String(line) }.joined(separator: "\n")
    }
}
