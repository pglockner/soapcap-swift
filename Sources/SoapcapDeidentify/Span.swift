import Foundation

/// A stretch of text to replace: where it is, what kind of thing it is
/// (FIRST_NAME, PHONE, DATE…) and how sure the finder was.
public struct Span: Equatable, Sendable {
    public var range: Range<String.Index>
    public var label: String
    public var confidence: Double

    public init(_ range: Range<String.Index>, _ label: String, confidence: Double = 1) {
        self.range = range
        self.label = label
        self.confidence = confidence
    }
}

/// Finds identifying text. The app's one is the on-device model; tests script one.
/// Labels come back in the form the tokens use (FIRST_NAME, not first_name).
public protocol PIIDetector: Sendable {
    func spans(in text: String) async throws -> [Span]
}
