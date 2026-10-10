import Foundation
import SoapcapCore

/// Which note models there are, and how to reach each.
public enum ModelCatalog {
    public static let bonsai = "bonsai"
    public static let defaultModel = "llama3.1:8b"

    /// What the clinician should know about a model soapcap's prompts were
    /// tested with; nil for any other.
    public static func description(of model: String) -> String? {
        switch model {
        case "llama3.1:8b":
            "Fast, usually under a minute. Often assumes a client's pronoun from their name; proofread pronouns and the Objective."
        case bonsai:
            "More careful: best at pronouns and at not inventing in-session reactions. Slower, a few minutes a note."
        default: nil
        }
    }

    /// `bonsai` is its own backend; every other name is a model in Ollama.
    public static func backend(for model: String, host: URL = OllamaBackend.defaultHost,
                               bonsai install: BonsaiBackend.Install = .standard) -> any NoteBackend {
        model == bonsai ? BonsaiBackend(install: install) : OllamaBackend(model: model, host: host)
    }

    /// The models that could draft right now: Bonsai if it is set up, then
    /// everything pulled into Ollama (tested or not).
    public static func installed(host: URL = OllamaBackend.defaultHost,
                                 bonsai install: BonsaiBackend.Install = .standard) async -> [String] {
        let pulled = (try? await OllamaBackend(model: "", host: host).models()) ?? []
        return (install.isPresent ? [bonsai] : []) + pulled.sorted()
    }

    /// Whether `model` is ready to draft, as a line for the checks screen.
    public static func check(_ model: String, host: URL = OllamaBackend.defaultHost,
                             bonsai install: BonsaiBackend.Install = .standard) async -> Check {
        let backend = backend(for: model, host: host, bonsai: install)
        do {
            try await backend.check()
            let caution = backend.cautions.first
            return Check("Note model", caution == nil ? .ok : .warning, caution ?? "\(backend.label) is ready to draft notes.")
        } catch {
            return Check("Note model", .failed, error.localizedDescription + "\nOr choose another model in Settings.")
        }
    }
}
