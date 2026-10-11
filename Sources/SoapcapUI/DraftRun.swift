import Foundation
import SoapcapCore
import SoapcapNote

/// The note model at work: one draft at a time, the memory in use
/// meanwhile, and stopping it so that its memory really is free.
@MainActor
final class DraftRun: ObservableObject {
    /// True while the model is working, which is when it can be stopped.
    @Published var isRunning = false
    /// How full memory is while a note is drafted; nil otherwise.
    @Published var memory: MemoryStatus?

    private let drafting: Drafting
    private let readMemory: () -> MemoryStatus?
    private var task: Task<DraftedNote, Error>?
    private var releasing: Task<Void, Never>?

    init(drafting: Drafting, memory: @escaping () -> MemoryStatus?) {
        self.drafting = drafting
        readMemory = memory
    }

    /// Drafts a note, or returns nil if `stop()` ended it first. A draft
    /// that fails frees the model before throwing, so a half-started one
    /// isn't left holding memory (or, for Bonsai, its port).
    func draft(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String,
               progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> DraftedNote? {
        let task = Task {
            // A model that is still stopping must be gone before another loads.
            await releasing?.value
            try Task.checkCancellation()
            return try await drafting.draft(format: format, transcript: transcript, minutes: minutes,
                                            systemLabel: systemLabel, progress: progress)
        }
        self.task = task
        isRunning = true
        // A model that outgrows memory slows to a crawl; show it happening.
        let watch = Task {
            while !Task.isCancelled, self.task == task {
                memory = readMemory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        let result = await task.result
        watch.cancel()
        guard self.task == task else { return nil }     // stopped, and stop() has tidied up
        self.task = nil; isRunning = false; memory = nil
        if case .failure = result { await release() }
        return try result.get()
    }

    /// Ends a draft in flight, if there is one, and starts freeing the
    /// model. The draft is over at once; wait for the returned task to know
    /// that the model has gone.
    @discardableResult
    func stop() -> Task<Void, Never> {
        task?.cancel()
        task = nil; isRunning = false; memory = nil
        return Task { await release() }
    }

    /// The model is otherwise kept loaded between drafts. However many ask
    /// at once, it is released once and each returns only when it has gone.
    private func release() async {
        if releasing == nil { releasing = Task { await drafting.release(); releasing = nil } }
        await releasing?.value
    }
}
