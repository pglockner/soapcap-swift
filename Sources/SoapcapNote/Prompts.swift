import Foundation

/// The prompt files, kept as data so they can be read and changed without
/// touching code. They are soapcap's, unchanged.
public enum Prompts {
    /// In the built app they sit in Contents/Resources/prompts; under
    /// `swift build` and `swift test`, in the package's resource bundle.
    static let directory: URL = {
        if let inApp = Bundle.main.resourceURL?.appendingPathComponent("prompts"),
           FileManager.default.fileExists(atPath: inApp.appendingPathComponent("soap.md").path) {
            return inApp
        }
        return Bundle.module.resourceURL!.appendingPathComponent("prompts")
    }()

    static func read(_ path: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
    }

    /// The transcript as it appears in a prompt. Prompts that put it first
    /// all begin with exactly this text.
    public static func opening(transcript: String) -> String { "TRANSCRIPT:\n" + transcript }

    /// The prose-draft prompt for `format`: the instructions, then the
    /// transcript, or the other way round with `transcriptFirst`.
    public static func draft(_ format: NoteFormat, transcript: String, transcriptFirst: Bool = false) throws -> String {
        let instructions = try read("\(format.rawValue).md").trimmingTrailingNewlines
        return transcriptFirst ? opening(transcript: transcript) + "\n\n" + instructions
            : instructions + "\n\n" + opening(transcript: transcript)
    }

    /// The SOAP Objective pass's prompt. Its own prompt because it does what
    /// the drafting rules forbid: judge affect, mood and speech from a transcript.
    public static func objective(transcript: String, transcriptFirst: Bool = false) throws -> String {
        let instructions = try read("objective.md").trimmingTrailingNewlines
        return (transcriptFirst ? opening(transcript: transcript) + "\n\n" + instructions
            : instructions + "\n\n" + opening(transcript: transcript)) + "\n"
    }

    static let objectiveFields = ["mental_status", "risk", "risk_kind"]

    /// The JSON schema the Objective pass's reply must match.
    public static func objectiveSchema() throws -> Data {
        let all = try JSONSerialization.jsonObject(with: Data(try read("structured/schema.json").utf8)) as? [String: Any] ?? [:]
        let schema: [String: Any] = ["type": "object", "properties": all.filter { objectiveFields.contains($0.key) },
                                     "required": objectiveFields]
        return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }
}

extension String {
    var trimmingTrailingNewlines: String { replacing(pattern: "\\n+$", with: "") }
}
