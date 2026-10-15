import Foundation
import SoapcapCore

/// Reads the JSON `yap` writes: `{"segments": [{speaker, start, end, id, text}]}`,
/// every field optional (a single-track transcription has no speaker).
/// The Core tests have the same reader, for soapcap's transcript cases.
enum YapJSON {
    private struct Document: Decodable { var segments: [Line]? }
    private struct Line: Decodable { var speaker: String?, start: Double?, end: Double?, id: Int?, text: String? }

    static func segments(_ data: Data) throws -> [Segment] {
        try JSONDecoder().decode(Document.self, from: data).segments?.map {
            Segment(speaker: $0.speaker ?? "Speaker", start: $0.start ?? 0, end: $0.end, id: $0.id ?? 0, text: $0.text ?? "")
        } ?? []
    }
}
