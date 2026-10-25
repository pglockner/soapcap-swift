import Foundation

/// One file of the de-identification model, pinned to an exact revision and checksum.
public struct ModelFile: Equatable, Sendable {
    public let name: String
    /// The Hugging Face repository it comes from.
    public let repo: String
    public let revision: String
    public let sha256: String

    public init(_ name: String, repo: String, revision: String, sha256: String) {
        self.name = name
        self.repo = repo
        self.revision = revision
        self.sha256 = sha256
    }

    var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(name)")! }
}

/// The de-identification model's files on this Mac.
public enum ModelFiles {
    /// Where the app keeps them. SOAPCAP_DEIDENTIFY_MODEL overrides.
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SOAPCAP_DEIDENTIFY_MODEL"] { return URL(fileURLWithPath: path) }
        return URL.applicationSupportDirectory.appending(path: "Soapcap/deidentify-model", directoryHint: .isDirectory)
    }

    /// OpenMed's PII model as soapcap tested it: the MLX weights from one
    /// repository, the tokenizer from the model they were converted from.
    public static let pinned: [ModelFile] = {
        let weights = "OpenMed/OpenMed-PII-ClinicalE5-Small-33M-v1-mlx", weightsRevision = "593ce409e3ffbe951404f274a0f4459cdf2a421d"
        let source = "OpenMed/OpenMed-PII-ClinicalE5-Small-33M-v1", sourceRevision = "2ea947130eb28d610ceb96472af0b694fce9c344"
        return [
            ModelFile("config.json", repo: weights, revision: weightsRevision,
                      sha256: "04a9234e83fec48eb9efef644abeb095c6c8c4296c7d089b9a5292647ab9d29f"),
            ModelFile("id2label.json", repo: weights, revision: weightsRevision,
                      sha256: "40f57c6fa3d84775c7d3cd58d6ef3c4736250261f08572cbbaef1290b577c898"),
            ModelFile("weights.safetensors", repo: weights, revision: weightsRevision,
                      sha256: "87fff672bfae2ee052b0c046b5cbe1bc14792b93eaeca2b2526ac6dd2926cdc9"),
            ModelFile("tokenizer.json", repo: source, revision: sourceRevision,
                      sha256: "435667fab0c06c165b1283ecb422497c37124f2d6a35b2ac73dc876332fc9518"),
            ModelFile("tokenizer_config.json", repo: source, revision: sourceRevision,
                      sha256: "bf9431564f2867411d0c5ec40cfaa1d73275a9847dbf34f23c8961b1f2981cc4"),
            ModelFile("special_tokens_map.json", repo: source, revision: sourceRevision,
                      sha256: "5d5b662e421ea9fac075174bb0688ee0d9431699900b90662acd44b2a350503a"),
        ]
    }()

    /// Whether every file is in place. Checksums are verified when the files
    /// are installed, not on every launch.
    public static func isReady(in directory: URL = ModelFiles.directory, files: [ModelFile] = pinned) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0.name).path) }
    }
}
