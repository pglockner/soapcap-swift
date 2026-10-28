import Foundation
import SoapcapCore

/// One of the note models the prompts were tested with: the name Settings
/// stores, what to call it, its file, and what it needs. All run on the
/// app's engine (`EngineBackend`).
public struct NoteModel: Equatable, Sendable {
    /// The name Settings stores.
    public let id: String
    /// What to call it on screen.
    public let displayName: String
    /// The file the app downloads.
    public let weights: PinnedFile
    /// Roughly how much memory it takes once loaded.
    public let memoryNeedGB: Double
    /// What the clinician should know about it.
    public let description: String
    /// See `EngineBackend.resumesFromSharedOpening`.
    public let resumesFromSharedOpening: Bool
    /// Flags this model needs from the engine beyond the ones every model gets.
    public let serverArguments: [String]

    /// The app's own copy of the file.
    public var ownWeights: URL { EngineBackend.Install.modelsDirectory.appendingPathComponent(weights.name) }

    /// The app's engine and its own copy of the file.
    public var install: EngineBackend.Install {
        EngineBackend.Install(server: EngineBackend.Install.server, weights: ownWeights)
    }

    /// Bonsai 2 27B, as soapcap tested it. Measured at 7.4 GB with the
    /// smallest context the app uses and 8.5 GB with the largest.
    public static let bonsai = NoteModel(
        id: "bonsai", displayName: "Bonsai",
        weights: PinnedFile(
            name: "Ternary-Bonsai-2-27B-PTQ1_0.gguf",
            url: URL(string: "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/65f27a86966957c534ea6ad12149286e01ca7cc0/Ternary-Bonsai-2-27B-PTQ1_0.gguf")!,
            sha256: "53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3", bytes: 5_946_648_928),
        memoryNeedGB: 8,
        description: "Slower, a few minutes a note, and needs the most memory.",
        resumesFromSharedOpening: true, serverArguments: [])

    /// Gemma 4 E4B Instruct at 4 bits, in unsloth's conversion; the default.
    /// Measured at 5–6.5 GB on the app's engine. Its attention looks back
    /// over a sliding window, so the engine can return to the end of the
    /// shared opening only from a checkpoint; without one taken at every
    /// request, the Objective pass reads the whole transcript again.
    public static let gemma = NoteModel(
        id: "gemma4-e4b", displayName: "Gemma 4 E4B",
        weights: PinnedFile(
            name: "gemma-4-E4B-it-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/bfc15c382204943c3a8fff0c750b94ae2364d7a3/gemma-4-E4B-it-Q4_K_M.gguf")!,
            sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87", bytes: 4_977_171_584),
        memoryNeedGB: 6.5,
        description: "Fast, under two minutes for a long session, and needs the least memory.",
        resumesFromSharedOpening: true, serverArguments: ["--checkpoint-min-step", "0"])

    /// Qwen3.5 9B at 4 bits, in unsloth's conversion. Measured at about
    /// 6 GB on the app's engine, rising to 8.5 GB on some sessions.
    public static let qwen = NoteModel(
        id: "qwen3.5-9b", displayName: "Qwen3.5 9B",
        weights: PinnedFile(
            name: "Qwen3.5-9B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/3885219b6810b007914f3a7950a8d1b469d598a5/Qwen3.5-9B-Q4_K_M.gguf")!,
            sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8", bytes: 5_680_522_464),
        memoryNeedGB: 8.5,
        description: "Writes a little differently from Gemma; about two minutes for a long session, and needs more memory.",
        resumesFromSharedOpening: true, serverArguments: [])

    /// Every model, the default first.
    public static let all = [gemma, qwen, bonsai]

    /// The model Settings means by `id`, if it is one of them.
    public static func named(_ id: String) -> NoteModel? {
        all.first { $0.id == id }
    }
}
