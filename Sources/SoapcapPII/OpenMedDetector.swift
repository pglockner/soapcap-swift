import Foundation
import OpenMedKit
import SoapcapDeidentify

/// OpenMed's on-device PII model, loaded from a folder that holds its
/// weights and tokenizer. It never uses the network.
public actor OpenMedDetector: PIIDetector {
    public static let confidence: Float = 0.5
    /// How one pass cuts the text: chunks of `limit` tokens, each sharing
    /// `overlap` with the next.
    public typealias Window = (limit: Int, overlap: Int)

    /// The detection pass: short chunks that half-overlap, so every word is
    /// at least a quarter-chunk from an edge in one of them.
    public static let detection: Window = (limit: 128, overlap: 64)
    /// The context pass: soapcap's long layout, just under the model's
    /// 512-token ceiling, which gives each word the most surrounding text.
    public static let context: Window = (limit: 480, overlap: 128)

    /// The text is read once per pass and the findings are merged. The
    /// model's score for a word shifts with what else is in its chunk, so
    /// one cut alone misses things another catches.
    ///
    /// soapcap's helper pairs the context pass with 256/32 instead. In this
    /// runtime that pair left an employer and an insurer in soapcap's sample
    /// 06; this pair removes everything the helper removes from its samples.
    public static let windows = [detection, context]

    private let directory: URL
    private let windows: [Window]
    private var model: OpenMed?

    public init(directory: URL = ModelFiles.directory, windows: [Window] = OpenMedDetector.windows) {
        self.directory = directory
        self.windows = windows
    }

    public func spans(in text: String) async throws -> [Span] {
        let model = try loaded()
        let windows = windows
        return try windows.flatMap { window in
            try model.extractPIIChunked(text, confidenceThreshold: Self.confidence,
                                        chunkTokenLimit: window.limit, tokenOverlap: window.overlap)
        }.compactMap { entity in
            // Offsets are Unicode scalars; a span must not split a character.
            guard let whole = entity.snappedToGraphemeBoundaries(in: text), let range = whole.range(in: text) else { return nil }
            return Span(range, Policy.canonicalLabel(for: whole.label), confidence: Double(whole.confidence))
        }
    }

    private func loaded() throws -> OpenMed {
        if let model { return model }
        let fresh = try OpenMed(backend: .mlx(modelDirectoryURL: directory), allowNetworkAccess: false)
        model = fresh
        return fresh
    }
}
