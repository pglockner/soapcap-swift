import Foundation

/// Bonsai 2 27B, served by a `llama-server` this backend starts for a note
/// and stops afterwards. Both the server build and the weights are set up
/// outside the app, by soapcap's tools/bonsai/install.sh.
public actor BonsaiBackend: NoteBackend {
    /// Where the two halves of a Bonsai setup are, and the local port to serve on.
    public struct Install: Equatable, Sendable {
        public var server: URL
        public var weights: URL
        public var port: Int

        public init(server: URL, weights: URL, port: Int = 18080) {
            self.server = server
            self.weights = weights
            self.port = port
        }

        /// Where soapcap's installer puts it.
        public static var standard: Install {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/soapcap/bonsai")
            return Install(server: dir.appendingPathComponent("llama.cpp/build/bin/llama-server"),
                           weights: dir.appendingPathComponent("Ternary-Bonsai-2-27B-PTQ1_0.gguf"))
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
        guard install.isPresent else {
            throw NoteError.notReady("Bonsai isn't set up. Expected llama-server at \(install.server.path) and the model at \(install.weights.path). Set it up with soapcap's tools/bonsai/install.sh.")
        }
        // Anything already answering here would silently draft the note with
        // whatever model it serves.
        if !isRunning, await healthy() != nil {
            throw NoteError.notReady("Something is already listening on port \(install.port). Stop it before drafting with Bonsai.")
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
                throw NoteError.notReady("llama-server exited while loading Bonsai. Its last lines:\n\(log.tail)")
            }
            // A draft given up on while loading must not leave the server behind.
            if Task.isCancelled { await stop(); throw CancellationError() }
            if await healthy() == true { return }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
        await stop()
        throw NoteError.notReady("Bonsai didn't finish loading within \(Int(loadTimeout))s.")
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 900

        let data: Data
        do { (data, _) = try await session.data(for: request) } catch {
            throw NoteError.requestFailed("The request to Bonsai failed: \(error.localizedDescription)")
        }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = reply["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? "\(error)"
            throw NoteError.requestFailed("Bonsai error: \(message)")
        }
        let choice = (reply["choices"] as? [[String: Any]])?.first
        let text = (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw NoteError.requestFailed("Bonsai returned no content.") }
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
