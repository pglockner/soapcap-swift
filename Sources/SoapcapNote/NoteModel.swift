import Foundation
import SoapcapCore

/// One of the two note models the prompts were tested with: the name
/// Settings stores, what to call it, its file, and what it needs. Both run
/// on the app's engine (`EngineBackend`); `llama3.1:8b` may be Ollama's
/// instead (see `ModelCatalog.backend`).
public struct NoteModel: Equatable, Sendable {
    /// The name Settings stores, and Ollama's name for it.
    public let id: String
    /// What to call it on screen.
    public let displayName: String
    /// The file the app downloads.
    public let weights: PinnedFile
    /// A copy something else installed, used where it is, if there may be one.
    public let elsewhere: URL?
    /// Roughly how much memory it takes once loaded.
    public let memoryNeedGB: Double
    /// What the clinician should know about it.
    public let description: String
    /// See `EngineBackend.resumesFromSharedOpening`.
    public let resumesFromSharedOpening: Bool

    /// The app's own copy of the file.
    public var ownWeights: URL { EngineBackend.Install.modelsDirectory.appendingPathComponent(weights.name) }

    /// The engine and the file: the app's own copy, or else the one
    /// something else installed.
    public var install: EngineBackend.Install {
        .found(servers: EngineBackend.Install.servers, weights: [ownWeights] + [elsewhere].compactMap { $0 })
    }

    /// Bonsai 2 27B, as soapcap tested it. Measured at 7.4 GB with the
    /// smallest context the app uses and 8.5 GB with the largest. A copy
    /// soapcap's installer made is used where it is.
    public static let bonsai = NoteModel(
        id: "bonsai", displayName: "Bonsai",
        weights: PinnedFile(
            name: "Ternary-Bonsai-2-27B-PTQ1_0.gguf",
            url: URL(string: "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/65f27a86966957c534ea6ad12149286e01ca7cc0/Ternary-Bonsai-2-27B-PTQ1_0.gguf")!,
            sha256: "53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3", bytes: 5_946_648_928),
        elsewhere: EngineBackend.Install.soapcapDirectory.appendingPathComponent("Ternary-Bonsai-2-27B-PTQ1_0.gguf"),
        memoryNeedGB: 8,
        description: "More careful: best at pronouns and at not inventing in-session reactions. Slower, a few minutes a note.",
        resumesFromSharedOpening: true)

    /// Llama 3.1 8B Instruct at 4 bits, in second-state's conversion. Of
    /// the files that need no sign-up it is the nearest to the copy Ollama
    /// serves, which the prompts were tested with: 276 of its 292 tensors
    /// are the same bytes, and so is the chat template. Measured at 6.5 GB
    /// on the app's engine with the smallest context the app uses; Ollama's
    /// copy is taken to need about the same. Its prompts go in the order
    /// Ollama gets them, as the two were compared.
    public static let llama = NoteModel(
        id: "llama3.1:8b", displayName: "llama3.1:8b",
        weights: PinnedFile(
            name: "Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/second-state/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/6d6118a261564da05fd7e651f4bc069eb7c38c20/Llama-3.1-8B-Instruct-Q4_K_M.gguf")!,
            sha256: "599024f21235045ea4ad7aecc5d46e794920e201d669328f577b1971cf98c904", bytes: 4_920_739_200),
        elsewhere: nil,
        memoryNeedGB: 6.5,
        description: "Fast, usually under a minute. Often assumes a client's pronoun from their name; proofread pronouns and the Objective.",
        resumesFromSharedOpening: false)

    /// The model Settings means by `id`, if it is one of the two.
    public static func named(_ id: String) -> NoteModel? {
        [bonsai, llama].first { $0.id == id }
    }
}
