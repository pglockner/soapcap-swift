import Foundation
import SoapcapCore

/// Which note models there are, and how to reach each.
public enum ModelCatalog {
    public static let bonsai = NoteModel.bonsai.id
    public static let defaultModel = NoteModel.gemma.id

    /// What to call a model on screen.
    public static func displayName(of model: String) -> String {
        NoteModel.named(model)?.displayName ?? model
    }

    /// What the clinician should know about each model.
    public static func description(of model: String) -> String {
        NoteModel.named(model)?.description ?? ""
    }

    /// Roughly how much memory a model takes once loaded; nil for a name
    /// that isn't one of the models.
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

    /// The app's engine running `model`, or the default model for a name
    /// that isn't one of them.
    public static func backend(for model: String) -> any NoteBackend {
        EngineBackend(NoteModel.named(model) ?? NoteModel.gemma)
    }

    /// The models that could draft right now: those whose file the app has
    /// downloaded and checked. They are the ones the prompts were tested
    /// with, and no other is offered.
    public static func installed(isPresent: (NoteModel) -> Bool = { $0.install.isPresent }) -> [String] {
        NoteModel.all.filter(isPresent).map(\.id)
    }

    /// Whether `model` is ready to draft, as a line for the checks screen.
    public static func check(_ model: String) async -> Check {
        let backend = backend(for: model)
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
