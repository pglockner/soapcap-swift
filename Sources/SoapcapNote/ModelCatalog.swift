import Foundation
import SoapcapCore

/// Which note models there are, and how to reach each.
public enum ModelCatalog {
    public static let bonsai = NoteModel.bonsai.id
    public static let defaultModel = NoteModel.llama.id

    /// What to call a model on screen.
    public static func displayName(of model: String) -> String {
        NoteModel.named(model)?.displayName ?? model
    }

    /// What the clinician should know about each of the two models.
    public static func description(of model: String) -> String {
        NoteModel.named(model)?.description ?? ""
    }

    /// Roughly how much memory a model takes once loaded; nil for any
    /// model but the two.
    public static func memoryNeedGB(of model: String) -> Double? {
        NoteModel.named(model)?.memoryNeedGB
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

    /// What the Ollama at `host` has pulled; nothing when it doesn't answer.
    public static func pulled(host: URL = OllamaBackend.defaultHost) async -> [String] {
        (try? await OllamaBackend(model: "", host: host).models()) ?? []
    }

    /// `bonsai` runs on the app's engine. So does the default model, from
    /// the app's own file, unless Ollama has it: a model Ollama already
    /// holds is used where it is. Every other name is a model in Ollama.
    public static func backend(for model: String, pulled: [String], host: URL = OllamaBackend.defaultHost,
                               bonsai: EngineBackend.Install = NoteModel.bonsai.install,
                               llama: EngineBackend.Install = NoteModel.llama.install) -> any NoteBackend {
        if model == self.bonsai { return EngineBackend(.bonsai, install: bonsai) }
        if model == defaultModel, !OllamaBackend.has(model, in: pulled) { return EngineBackend(.llama, install: llama) }
        return OllamaBackend(model: model, host: host)
    }

    public static func backend(for model: String, host: URL = OllamaBackend.defaultHost) async -> any NoteBackend {
        backend(for: model, pulled: model == bonsai ? [] : await pulled(host: host), host: host)
    }

    /// The models that could draft right now: Bonsai if it is set up, and
    /// the default model if the app or Ollama has its file. They are the two
    /// the prompts were tested with, and no other is offered.
    public static func installed(pulled: [String], bonsai: EngineBackend.Install = NoteModel.bonsai.install,
                                 llama: EngineBackend.Install = NoteModel.llama.install) -> [String] {
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
