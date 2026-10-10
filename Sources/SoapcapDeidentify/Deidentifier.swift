import Foundation

public struct Deidentified: Equatable, Sendable {
    public let text: String
    /// One line, e.g. "redacted 4 span(s): FIRST_NAME x3, PHONE x1".
    public let summary: String

    public init(text: String, summary: String) {
        self.text = text
        self.summary = summary
    }
}

public enum DeidentifyError: Error, LocalizedError {
    case lineCountChanged

    public var errorDescription: String? { "De-identifying changed the number of lines, so the result was discarded." }
}

/// Replaces identifying text with numbered tokens. Best effort: the model
/// misses things, so the result still needs reading before it is shared.
/// Any failure throws; text is never passed through unchanged by mistake.
public struct Deidentifier: Sendable {
    let detector: any PIIDetector

    public init(detector: any PIIDetector) { self.detector = detector }

    public func deidentify(_ text: String, kind: LabeledText.Kind) async throws -> Deidentified {
        let labeled = LabeledText(text, kind: kind)
        let body = labeled.body
        var spans: [Span] = []
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            spans = SpanFilter.usable(try await detector.spans(in: body), in: body) + Rules.spans(in: body)
            spans += RepeatNames.spans(in: body, found: spans)
            spans = SpanFilter.splitAtLineBreaks(spans, in: body)
        }
        let (redacted, summary) = Redactor.redact(body, spans)
        guard let joined = labeled.rejoined(with: redacted) else { throw DeidentifyError.lineCountChanged }
        return Deidentified(text: joined, summary: summary)
    }
}
