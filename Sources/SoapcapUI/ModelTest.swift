import Foundation
import SoapcapNote

/// Trying the chosen note model on the sample session: a note is drafted and
/// judged, and nothing of it is kept. It goes through the `DraftRun` a
/// session's draft uses, so the two never load a model each; a session's
/// draft takes the model from a test that is running.
@MainActor
final class ModelTest: ObservableObject {
    enum State: Equatable {
        case idle
        /// What the model is doing just now, and how much it has written
        /// in that step when it says.
        case running(String, tokens: Int? = nil)
        case good(model: String, seconds: Int)
        case problem(model: String, reasons: [String])
    }

    @Published private(set) var state = State.idle
    /// The note the last test drafted, to read; nil if it never got one.
    @Published private(set) var note: String?
    /// True while a session is being recorded, which is no time to load a model.
    @Published var isBlocked = false

    let run: DraftRun
    private let settings: SessionSettings
    private let cautions: (String) async -> [String]
    private let now: () -> Date
    /// Bumped by each start and stop, so a test that was stopped can't
    /// report over the one after it.
    private var current = 0

    /// `cautions` are what a model's notes are always cautioned about (an
    /// untested model, say); they are no fault of the note being judged.
    init(run: DraftRun, settings: SessionSettings,
         cautions: @escaping (String) async -> [String] = { ModelCatalog.backend(for: $0).cautions },
         now: @escaping () -> Date = Date.init) {
        self.run = run
        self.settings = settings
        self.cautions = cautions
        self.now = now
    }

    var isRunning: Bool { if case .running = state { true } else { false } }
    var canStart: Bool { !isRunning && !run.isRunning && !isBlocked }

    func start() {
        guard canStart else { return }
        let model = settings.noteModel, began = now()
        current += 1
        let mine = current
        state = .running("Starting…")
        note = nil
        Task {
            let standing = await cautions(model)
            guard mine == current else { return }
            do {
                // Nil when stopped, or when a session's draft took the model.
                guard let drafted = try await run.draft(format: .soap, transcript: try SampleSession.transcript(),
                                                        minutes: SampleSession.minutes, systemLabel: SampleSession.systemLabel,
                                                        progress: { progress in Task { @MainActor in self.show(progress, mine) } })
                else {
                    if mine == current { state = .idle }
                    return
                }
                guard mine == current else { return }
                note = drafted.text
                let reasons = SampleSession.problems(in: drafted, cautions: standing)
                state = reasons.isEmpty ? .good(model: model, seconds: Int(now().timeIntervalSince(began).rounded()))
                    : .problem(model: model, reasons: reasons)
            } catch {
                guard mine == current else { return }
                state = .problem(model: model, reasons: [error.localizedDescription])
            }
            // A test is a one-off, so the model isn't kept loaded after it.
            if !run.isRunning { run.stop() }
        }
    }

    func stop() {
        guard isRunning else { return }
        current += 1
        state = .idle
        run.stop()
    }

    private func show(_ progress: DraftProgress, _ mine: Int) {
        guard mine == current, isRunning else { return }
        state = .running(progress.title, tokens: progress.tokens)
    }

    /// For previews.
    func show(_ state: State, note: String? = nil) {
        self.state = state
        self.note = note
    }
}
