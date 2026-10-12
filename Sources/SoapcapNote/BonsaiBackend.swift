import Foundation
import SoapcapCore

/// A note model served by a `llama-server` this backend starts for a note
/// and stops afterwards: Bonsai 2 27B unless told otherwise. The server
/// ships inside the app (see engine.sh); the weights are a download.
public actor BonsaiBackend: NoteBackend {
    /// Where the server and a model's weights are, and the local port to serve on.
    public struct Install: Equatable, Sendable {
        public var server: URL
        public var weights: URL
        public var port: Int

        public init(server: URL, weights: URL, port: Int = 18080) {
            self.server = server
            self.weights = weights
            self.port = port
        }

        /// Bonsai 2 27B's weights, as soapcap tested them.
        public static let weights = PinnedFile(
            name: "Ternary-Bonsai-2-27B-PTQ1_0.gguf",
            url: URL(string: "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/65f27a86966957c534ea6ad12149286e01ca7cc0/Ternary-Bonsai-2-27B-PTQ1_0.gguf")!,
            sha256: "53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3", bytes: 5_946_648_928)

        /// Where the app keeps the note models it downloads.
        public static var modelsDirectory: URL {
            URL.applicationSupportDirectory.appending(path: "Soapcap/note-models", directoryHint: .isDirectory)
        }

        /// The app's own copy of the weights, and the one soapcap's installer makes.
        public static var ownWeights: URL { modelsDirectory.appendingPathComponent(weights.name) }
        public static var soapcapWeights: URL { soapcapDirectory.appendingPathComponent(weights.name) }
        static var soapcapDirectory: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/soapcap/bonsai")
        }

        /// Llama 3.1 8B Instruct at 4 bits, in second-state's conversion.
        /// Of the files that need no sign-up it is the nearest to the copy
        /// Ollama serves, which the prompts were tested with: 276 of its
        /// 292 tensors are the same bytes, and so is the chat template.
        public static let llamaWeights = PinnedFile(
            name: "Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/second-state/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/6d6118a261564da05fd7e651f4bc069eb7c38c20/Llama-3.1-8B-Instruct-Q4_K_M.gguf")!,
            sha256: "599024f21235045ea4ad7aecc5d46e794920e201d669328f577b1971cf98c904", bytes: 4_920_739_200)
        public static var ownLlamaWeights: URL { modelsDirectory.appendingPathComponent(llamaWeights.name) }

        /// The engine inside the app, or else the one soapcap's installer built.
        /// SOAPCAP_ENGINE names a different llama-server, for trying a build.
        static var servers: [URL] {
            let named = ProcessInfo.processInfo.environment["SOAPCAP_ENGINE"].map { [URL(fileURLWithPath: $0)] } ?? []
            return named + [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server"),
                            soapcapDirectory.appendingPathComponent("llama.cpp/build/bin/llama-server")]
        }

        /// Bonsai: the app's own copy of the weights, or else the one
        /// soapcap's installer made, used where it is.
        public static var standard: Install { found(servers: servers, weights: [ownWeights, soapcapWeights]) }

        /// Llama 3.1 on the same engine, from the app's own copy of the weights.
        public static var llama: Install { found(servers: servers, weights: [ownLlamaWeights]) }

        /// The first of each that is there. When none is, the first, so that
        /// what gets reported missing is the place the app would put it.
        static func found(servers: [URL], weights: [URL]) -> Install {
            func first(_ urls: [URL]) -> URL { urls.first { FileManager.default.fileExists(atPath: $0.path) } ?? urls[0] }
            return Install(server: first(servers), weights: first(weights))
        }

        public var isPresent: Bool {
            FileManager.default.isExecutableFile(atPath: server.path) && FileManager.default.fileExists(atPath: weights.path)
        }

        var url: URL { URL(string: "http://127.0.0.1:\(port)")! }
    }

    public nonisolated let install: Install
    public static let displayName = "Bonsai"
    public nonisolated let label: String
    public nonisolated let cautions: [String] = []
    /// llama-server keeps its place only near the end of each prompt, so a
    /// transcript in the middle of one is read again by the next request.
    /// Measured on a 22-minute session: the Objective pass took 97 s
    /// re-reading it and 43 s resuming after it.
    public nonisolated let resumesFromSharedOpening: Bool
    private let session: URLSession
    /// How long to wait for the model to load, and how often to ask.
    private let loadTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private var process: Process?
    private var context = 0
    /// Made afresh for each server and known only to it and this app.
    /// Without a key the server answers any program on this Mac, and any
    /// web page open in a browser.
    private var key = ""
    private let log = LogTail()

    /// The defaults are Bonsai's. The same server runs any GGUF model, so a
    /// different one is a different `install`, with its own name.
    public init(install: Install = .standard, label: String = BonsaiBackend.displayName,
                resumesFromSharedOpening: Bool = true, session: URLSession = .shared,
                loadTimeout: TimeInterval = 180, pollInterval: TimeInterval = 1) {
        self.install = install
        self.label = label
        self.resumesFromSharedOpening = resumesFromSharedOpening
        self.session = session
        self.loadTimeout = loadTimeout
        self.pollInterval = pollInterval
    }

    private var isRunning: Bool { process?.isRunning ?? false }

    private func healthy() async -> Bool? {
        struct Health: Decodable { var status: String? }
        var request = URLRequest(url: install.url.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return (try? JSONDecoder().decode(Health.self, from: data))?.status == "ok"
    }

    public func check() async throws {
        guard FileManager.default.fileExists(atPath: install.weights.path) else {
            throw NoteError.notReady("\(label)'s model file isn't on this Mac. Get it in Settings (Cmd-comma).")
        }
        guard FileManager.default.isExecutableFile(atPath: install.server.path) else {
            throw NoteError.notReady("The note engine is missing: expected llama-server at \(install.server.path).")
        }
        // Anything already answering here would silently draft the note with
        // whatever model it serves.
        if !isRunning, await healthy() != nil {
            throw NoteError.notReady("Something is already listening on port \(install.port). Stop it before drafting with \(label).")
        }
    }

    /// Launches the server with a context of at least 8192 tokens and waits
    /// until the model has loaded. A server still running from an earlier
    /// draft is reused when its context is big enough. The flags are the ones
    /// soapcap's prompts were tested with.
    public func start(context wanted: Int) async throws {
        let wanted = max(wanted, 8192)
        if isRunning, context >= wanted { return }
        await stop()
        try await check()
        try Task.checkCancellation()

        let server = Process()
        server.executableURL = install.server
        server.arguments = ["-m", install.weights.path, "--host", "127.0.0.1", "--port", String(install.port),
                            "-ngl", "99", "-c", String(wanted), "--parallel", "1",
                            "--cache-type-k", "q8_0", "--cache-type-v", "q8_0"]
        key = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        // In its environment, not its arguments, which any process can list.
        server.environment = ProcessInfo.processInfo.environment.merging(["LLAMA_API_KEY": key]) { _, new in new }
        let output = Pipe()
        server.standardOutput = output
        server.standardError = output
        server.standardInput = FileHandle.nullDevice
        log.follow(output)
        do { try server.run() } catch {
            throw NoteError.notReady("Couldn't start llama-server: \(error.localizedDescription)")
        }
        process = server
        context = wanted

        let deadline = Date().addingTimeInterval(loadTimeout)
        while Date() < deadline {
            guard server.isRunning else {
                await stop()
                throw NoteError.notReady("llama-server exited while loading \(label). Its last lines:\n\(log.tail)")
            }
            // A draft given up on while loading must not leave the server behind.
            if Task.isCancelled { await stop(); throw CancellationError() }
            if await healthy() == true { return }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
        await stop()
        throw NoteError.notReady("\(label) didn't finish loading within \(Int(loadTimeout))s.")
    }

    /// One chat request to the running server. Thinking is always off: with
    /// it on a note takes many minutes longer, and the prompts were tested
    /// without it. The server doesn't stream here, so `tokens` is not called.
    public func request(prompt: String, cap: Int, schema: Data?, tokens: @escaping @Sendable (Int) -> Void) async throws -> ModelReply {
        var body: [String: Any] = [
            "messages": [["role": "user", "content": prompt]], "stream": false,
            "chat_template_kwargs": ["enable_thinking": false],
            "top_p": 0.8, "top_k": 20, "max_tokens": cap, "temperature": schema == nil ? 0.7 : 0.3,
        ]
        if let schema {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["schema": try JSONSerialization.jsonObject(with: schema)]]
        }
        var request = URLRequest(url: install.url.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 900

        let data: Data
        do { (data, _) = try await session.data(for: request) } catch {
            throw NoteError.requestFailed("The request to \(label) failed: \(error.localizedDescription)")
        }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = reply["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? "\(error)"
            throw NoteError.requestFailed("\(label) error: \(message)")
        }
        let choice = (reply["choices"] as? [[String: Any]])?.first
        let text = (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw NoteError.requestFailed("\(label) returned no content.") }
        return ModelReply(text: text, cutOff: choice?["finish_reason"] as? String == "length")
    }

    /// Stops the server and waits for it, so its memory is released before
    /// anything else loads. llama-server finishes an in-flight request before
    /// honouring a polite stop; it gets 3 seconds, then is killed.
    public func stop() async {
        guard let server = process else { return }
        process = nil
        context = 0
        guard server.isRunning else { return }
        server.terminate()
        for _ in 0..<30 where server.isRunning { await Self.wait(milliseconds: 100) }
        if server.isRunning { kill(server.processIdentifier, SIGKILL) }
        // Not waitUntilExit(): called from here it can wait forever on a
        // process that has already gone, which would hang the app at quit.
        for _ in 0..<20 where server.isRunning { await Self.wait(milliseconds: 50) }
    }

    /// Waits even when the caller has been cancelled. Task.sleep returns at
    /// once there, which would kill the server without giving it its 3
    /// seconds and return before it had gone.
    private static func wait(milliseconds: Int) async {
        await withCheckedContinuation { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { done.resume() }
        }
    }
}

/// Keeps the last part of a process's output in memory, for an error message.
/// Nothing is written to disk.
final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func follow(_ pipe: Pipe) {
        lock.withLock { text = "" }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.lock.withLock {
                self?.text += String(decoding: data, as: UTF8.self)
                if let text = self?.text, text.count > 2000 { self?.text = String(text.suffix(2000)) }
            }
        }
    }

    /// The last five lines.
    var tail: String {
        lock.withLock { text.split(separator: "\n").suffix(5).joined(separator: "\n") }
    }
}
