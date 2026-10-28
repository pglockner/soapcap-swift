import Foundation

/// One reply from a note model.
public struct ModelReply: Equatable, Sendable {
    public var text: String
    /// The output cap cut the reply off before the model finished.
    public var cutOff: Bool

    public init(text: String, cutOff: Bool = false) {
        self.text = text
        self.cutOff = cutOff
    }
}

public enum NoteError: Error, LocalizedError, Equatable {
    /// The model can't be used as things stand; the message says what to do.
    case notReady(String)
    case requestFailed(String)
    case emptyNote

    public var errorDescription: String? {
        switch self {
        case .notReady(let why), .requestFailed(let why): why
        case .emptyNote: "The model returned an empty note."
        }
    }
}

/// A local model that drafts notes. `EngineBackend` is the one the app
/// uses; tests stand in their own.
public protocol NoteBackend: Sendable {
    /// The model's name as shown while drafting.
    var label: String { get }
    /// Things the clinician should know before trusting this model's note.
    var cautions: [String] { get }
    /// Throws `NoteError.notReady` unless the model could draft right now.
    /// Loads nothing, so it is quick.
    func check() async throws
    /// Gets the model ready for a note's requests, each within `context` tokens.
    func start(context: Int) async throws
    /// One request. `cap` is the output cap in tokens: without one, a model
    /// that starts repeating itself runs until the request times out.
    /// `schema`, if given, is a JSON schema the reply must match. `tokens` is
    /// called with a running count when the backend can stream.
    func request(prompt: String, cap: Int, schema: Data?, tokens: @escaping @Sendable (Int) -> Void) async throws -> ModelReply
    /// Frees the model's memory. Safe to call when nothing is loaded.
    func stop() async
    /// True for a model that can skip text it has already read only when an
    /// earlier request ended at that text. A note with two passes then
    /// reads the transcript once on its own and starts both prompts with
    /// it, instead of reading it in full for each pass.
    var resumesFromSharedOpening: Bool { get }
}

public extension NoteBackend {
    var resumesFromSharedOpening: Bool { false }
}

public extension URLSession {
    /// What the note backends reach their models through. It keeps nothing
    /// it sends or receives. The shared session files requests and replies
    /// in the app's cache folder on disk, and a request to a note model is
    /// the transcript.
    static let keepingNothing: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
