import Foundation
import OpenMedKit
import SoapcapDeidentify

/// OpenMed's on-device PII model, loaded from a folder that holds its
/// weights and tokenizer. It never uses the network.
public actor OpenMedDetector: PIIDetector {
    public static let confidence: Float = 0.5
    /// Detection runs under two chunk-window layouts (token limit, overlap)
    /// and the results are merged. Neither is strictly better: each catches a
    /// phone number the other misses, because they put different text near a
    /// chunk boundary. 480 leaves headroom under the model's 512-token ceiling.
    /// The third, smaller layout is not in soapcap's helper: this runtime
    /// cuts chunks differently, and without it an employer and an insurer
    /// that soapcap removes from its sample transcripts were left in.
    public static let windows = [(limit: 256, overlap: 32), (limit: 480, overlap: 128), (limit: 128, overlap: 64)]

    private let directory: URL
    private var model: OpenMed?

    public init(directory: URL = ModelFiles.directory) { self.directory = directory }

    public func spans(in text: String) async throws -> [Span] {
        let model = try loaded()
        return try Self.windows.flatMap { window in
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
