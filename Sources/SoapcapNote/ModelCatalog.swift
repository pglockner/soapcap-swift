import Foundation
import SoapcapCore

/// Which note models there are, and how to reach each.
public enum ModelCatalog {
    public static let bonsai = "bonsai"
    public static let defaultModel = "llama3.1:8b"

    /// What to call a model on screen.
    public static func displayName(of model: String) -> String {
        model == bonsai ? BonsaiBackend.displayName : model
    }

    /// What the clinician should know about each of the two models.
    public static func description(of model: String) -> String {
        model == bonsai
            ? "More careful: best at pronouns and at not inventing in-session reactions. Slower, a few minutes a note."
            : "Fast, usually under a minute. Often assumes a client's pronoun from their name; proofread pronouns and the Objective."
    }

    /// Roughly how much memory a model takes once loaded. Bonsai measured
    /// at 7.4 GB with the smallest context the app uses and 8.5 GB with the
    /// largest. The default model was measured on the app's engine; Ollama's
    /// copy is taken to need about the same, since the Mac's memory is
    /// short either way.
    public static func memoryNeedGB(of model: String) -> Double? {
        switch model {
        case bonsai: 8
        case defaultModel: defaultModelMemoryGB
        default: nil
        }
    }

    /// What to say before drafting with `model` when memory is short, or nil.
    public static func memoryAdvice(for model: String, memory: MemoryStatus?) -> String? {
        guard let memory, let need = memoryNeedGB(of: model) else { return nil }
        return memory.advice(beforeLoading: displayName(of: model), needGB: need)
    }

    /// What to ask before drafting with `model` when memory is very short, or nil.
    public static func memoryQuestion(for model: String, memory: MemoryStatus?) -> String? {
        guard let memory, let need = memoryNeedGB(of: model) else { return nil }
        return memory.question(beforeLoading: displayName(of: model), needGB: need)
    }

    /// How much memory this Mac has and has free, as a line for the checks
    /// screen, with the advice for `model` when it is short.
    public static func memoryCheck(_ memory: MemoryStatus?, model: String) -> Check {
        guard let memory else { return Check("Memory", .warning, "Couldn't read how much memory this Mac has.") }
        let size = String(format: "%.0f GB, about %.0f GB free now.", memory.totalGB, memory.availableGB.rounded(.down))
        if let advice = memoryAdvice(for: model, memory: memory) { return Check("Memory", .warning, size + " " + advice) }
        return Check("Memory", .ok, size)
    }

    /// Roughly what the default model takes on the app's engine, measured
    /// with the smallest context the app uses.
    public static let defaultModelMemoryGB = 6.5

    /// What the Ollama at `host` has pulled; nothing when it doesn't answer.
    public static func pulled(host: URL = OllamaBackend.defaultHost) async -> [String] {
        (try? await OllamaBackend(model: "", host: host).models()) ?? []
    }

    /// `bonsai` runs on the app's engine. So does the default model, from
    /// the app's own file, unless Ollama has it: a model Ollama already
    /// holds is used where it is. Every other name is a model in Ollama.
    public static func backend(for model: String, pulled: [String], host: URL = OllamaBackend.defaultHost,
                               bonsai: BonsaiBackend.Install = .standard,
                               llama: BonsaiBackend.Install = .llama) -> any NoteBackend {
        if model == self.bonsai { return BonsaiBackend(install: bonsai) }
        if model == defaultModel, !OllamaBackend.has(model, in: pulled) {
            // Prompts in the order Ollama gets them, as the two were compared.
            return BonsaiBackend(install: llama, label: model, resumesFromSharedOpening: false)
        }
        return OllamaBackend(model: model, host: host)
    }

    public static func backend(for model: String, host: URL = OllamaBackend.defaultHost) async -> any NoteBackend {
        backend(for: model, pulled: model == bonsai ? [] : await pulled(host: host), host: host)
    }

    /// The models that could draft right now: Bonsai if it is set up, and
    /// the default model if the app or Ollama has its file. They are the two
    /// the prompts were tested with, and no other is offered.
    public static func installed(pulled: [String], bonsai: BonsaiBackend.Install = .standard,
                                 llama: BonsaiBackend.Install = .llama) -> [String] {
        let hasDefault = llama.isPresent || OllamaBackend.has(defaultModel, in: pulled)
        return (bonsai.isPresent ? [self.bonsai] : []) + (hasDefault ? [defaultModel] : [])
    }

    /// The models that could draft right now, asking the Ollama at `host` what it has.
    public static func installed(host: URL) async -> [String] {
        installed(pulled: await pulled(host: host))
    }

    /// Whether `model` is ready to draft, as a line for the checks screen.
    public static func check(_ model: String, host: URL = OllamaBackend.defaultHost) async -> Check {
        let backend = await backend(for: model, host: host)
        do {
            try await backend.check()
            let caution = backend.cautions.first
            return Check("Note model", caution == nil ? .ok : .warning, caution ?? "\(backend.label) is ready to draft notes.")
        } catch {
            return Check("Note model", .failed, error.localizedDescription + "\nOr choose another model in Settings.",
                         fix: Check.Fix(label: "Open Settings", action: .showSettings))
        }
    }
}
