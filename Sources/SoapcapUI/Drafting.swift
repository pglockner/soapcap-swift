import Foundation
import SoapcapNote

/// What the session needs from note drafting; `ModelDrafting` in the app, a
/// scripted stand-in in tests.
@MainActor protocol Drafting: AnyObject {
    func draft(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String,
               progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> DraftedNote
    /// Frees the model's memory. It is otherwise kept loaded between drafts,
    /// so that drafting again doesn't wait for it to load.
    func release() async
}

/// Drafts with whichever model Settings names, switching when that changes.
@MainActor final class ModelDrafting: Drafting {
    private let settings: SessionSettings
    private var loaded: (model: String, host: URL, backend: any NoteBackend)?

    init(settings: SessionSettings) { self.settings = settings }

    func draft(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String,
               progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> DraftedNote {
        let model = settings.noteModel, host = settings.ollamaHost
        if let loaded, loaded.model != model || loaded.host != host { await release() }
        let backend = loaded?.backend ?? ModelCatalog.backend(for: model, host: host)
        loaded = (model, host, backend)
        var drafter = NoteDrafter(backend: backend)
        drafter.systemLabel = systemLabel
        drafter.sessionType = settings.sessionType
        return try await drafter.draft(format: format, transcript: transcript, minutes: minutes, progress: progress)
    }

    func release() async {
        await loaded?.backend.stop()
        loaded = nil
    }
}
