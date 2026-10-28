import Combine
import Foundation
import SoapcapCore
import SoapcapNote

/// Getting one model file onto this Mac, and off it again, for Settings
/// to show and start.
@MainActor
final class ModelDownload: ObservableObject {
    enum State: Equatable {
        case missing
        case working(FetchProgress)
        case failed(String)
        /// The app's own copy is in place.
        case ready
    }

    typealias Fetch = @Sendable (PinnedFile, URL, @escaping @Sendable (FetchProgress) -> Void) async throws -> Void

    /// One for each note model's weights, in `NoteModel.all`'s order, made
    /// once so that every view shows the same download.
    static let all = NoteModel.all.map { ModelDownload(model: $0) }

    /// Fires when any of them changes, and once at once, for a view that
    /// lists the models on this Mac.
    static var changes: AnyPublisher<Void, Never> {
        Publishers.MergeMany(all.map { $0.$state.map { _ in () } }).eraseToAnyPublisher()
    }

    @Published private(set) var state = State.missing
    let file: PinnedFile
    private let target: URL
    private let fetch: Fetch
    private var task: Task<Void, Never>?

    init(file: PinnedFile, target: URL, fetch: @escaping Fetch = { try await Fetcher().fetch($0, to: $1, progress: $2) }) {
        self.file = file
        self.target = target
        self.fetch = fetch
        refresh()
    }

    convenience init(model: NoteModel) {
        self.init(file: model.weights, target: model.ownWeights)
    }

    /// True when the model can be used.
    var isInstalled: Bool { state == .ready }
    /// How much an attempt that was stopped has already brought in.
    var keptBytes: Int64 { Fetcher.size(of: Fetcher.part(of: target)) }
    /// Room on the disk the model would go to.
    var freeBytes: Int64? { Fetcher.freeBytes(target.deletingLastPathComponent()) }

    /// Looks at the disk again, unless a download is running.
    func refresh() {
        if case .working = state { return }
        state = FileManager.default.fileExists(atPath: target.path) ? .ready : .missing
    }

    /// Downloads the file, carrying on from where a stopped attempt got to.
    func start() {
        if case .working = state { return }
        state = .working(FetchProgress(bytes: keptBytes, total: file.bytes))
        task = Task {
            do {
                try await fetch(file, target) { progress in
                    Task { @MainActor in
                        if case .working = self.state { self.state = .working(progress) }
                    }
                }
                state = .ready
            } catch is CancellationError {
                state = .missing
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a download. What has arrived is kept for next time.
    func stop() { task?.cancel() }

    /// Deletes the app's copy and anything a stopped download left.
    func remove() {
        task?.cancel()
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.removeItem(at: Fetcher.part(of: target))
        state = .missing
        refresh()
    }

    /// For previews.
    func show(_ state: State) { self.state = state }
}
