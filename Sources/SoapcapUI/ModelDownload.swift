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
        /// A copy something else installed is on this Mac, and is used where it is.
        case elsewhere
    }

    typealias Fetch = @Sendable (PinnedFile, URL, @escaping @Sendable (FetchProgress) -> Void) async throws -> Void

    /// Bonsai's weights: the app's copy, or the one soapcap's installer made.
    static let bonsai = ModelDownload(file: BonsaiBackend.Install.weights, target: BonsaiBackend.Install.ownWeights,
                                      elsewhere: BonsaiBackend.Install.soapcapWeights)

    /// The default model's weights, for a Mac whose Ollama doesn't have it.
    static let llama = ModelDownload(file: BonsaiBackend.Install.llamaWeights, target: BonsaiBackend.Install.ownLlamaWeights)

    @Published private(set) var state = State.missing
    let file: PinnedFile
    private let target: URL
    private let elsewhere: URL?
    private let fetch: Fetch
    private var task: Task<Void, Never>?

    init(file: PinnedFile, target: URL, elsewhere: URL? = nil, fetch: @escaping Fetch = { try await Fetcher().fetch($0, to: $1, progress: $2) }) {
        self.file = file
        self.target = target
        self.elsewhere = elsewhere
        self.fetch = fetch
        refresh()
    }

    /// True when the model can be used, whoever put it there.
    var isInstalled: Bool { state == .ready || state == .elsewhere }
    /// How much an attempt that was stopped has already brought in.
    var keptBytes: Int64 { Fetcher.size(of: Fetcher.part(of: target)) }
    /// Room on the disk the model would go to.
    var freeBytes: Int64? { Fetcher.freeBytes(target.deletingLastPathComponent()) }

    /// Looks at the disk again, unless a download is running.
    func refresh() {
        if case .working = state { return }
        let fm = FileManager.default
        state = fm.fileExists(atPath: target.path) ? .ready
            : elsewhere.map({ fm.fileExists(atPath: $0.path) }) == true ? .elsewhere : .missing
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

    /// Deletes the app's copy and anything a stopped download left. A copy
    /// that something else installed is never touched.
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
