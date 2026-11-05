import Foundation
import SoapcapCore

/// A note model served by the app's engine, a `llama-server` this backend
/// starts for a note and stops afterwards. The server ships inside the app
/// (see engine.sh); the model's file is a download. Which model, and what
/// is known about it, is a `NoteModel`.
public actor EngineBackend: NoteBackend {
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

        /// Where the app keeps the note models it downloads.
        public static var modelsDirectory: URL {
            URL.applicationSupportDirectory.appending(path: "Soapcap/note-models", directoryHint: .isDirectory)
        }

        /// The engine inside the app. SOAPCAP_ENGINE names a different
        /// llama-server, for trying a build.
        static var server: URL {
            ProcessInfo.processInfo.environment["SOAPCAP_ENGINE"].map { URL(fileURLWithPath: $0) }
                ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        }

        public var isPresent: Bool {
            FileManager.default.isExecutableFile(atPath: server.path) && FileManager.default.fileExists(atPath: weights.path)
        }

        var url: URL { URL(string: "http://127.0.0.1:\(port)")! }
    }

    public nonisolated let install: Install
    public nonisolated let label: String
    public nonisolated let cautions: [String] = []
    /// llama-server keeps its place only near the end of each prompt, so a
    /// transcript in the middle of one is read again by the next request.
    /// Measured on a 22-minute session: the Objective pass took 97 s
    /// re-reading it and 43 s resuming after it.
    public nonisolated let resumesFromSharedOpening: Bool
    /// The model's own flags, after the ones every model gets.
    nonisolated let serverArguments: [String]
    nonisolated let session: URLSession
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
    /// The GPU ran out of memory: the server can compute nothing more, so it
    /// has been stopped, and every request fails with this until `start`.
    private var fault: NoteError?
    /// Why the loaded model may fail on this Mac's GPU, if it may.
    private var gpuWarning: String?
    /// The model to suggest instead when this one runs out of GPU memory.
    nonisolated let lighter: String?

    /// One of the note models, from where it was found unless `install` says.
    public init(_ model: NoteModel, install: Install? = nil) {
        self.init(install: install ?? model.install, label: model.displayName,
                  resumesFromSharedOpening: model.resumesFromSharedOpening, serverArguments: model.serverArguments,
                  lighter: model.lighter?.displayName)
    }

    /// Any GGUF model: the same server runs them all.
    public init(install: Install, label: String,
                resumesFromSharedOpening: Bool = true, serverArguments: [String] = [], lighter: String? = nil,
                session: URLSession = .keepingNothing, loadTimeout: TimeInterval = 180, pollInterval: TimeInterval = 1) {
        self.install = install
        self.label = label
        self.resumesFromSharedOpening = resumesFromSharedOpening
        self.serverArguments = serverArguments
        self.lighter = lighter
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
    /// soapcap's prompts were tested with, and `-lv 4`, under which the
    /// server logs its GPU memory (never the prompt).
    public func start(context wanted: Int) async throws {
        let wanted = max(wanted, 8192)
        if isRunning, context >= wanted { return }
        await stop()
        fault = nil
        gpuWarning = nil
        try await check()
        try Task.checkCancellation()

        let server = Process()
        server.executableURL = install.server
        server.arguments = ["-m", install.weights.path, "--host", "127.0.0.1", "--port", String(install.port),
                            "-ngl", "99", "-c", String(wanted), "--parallel", "1",
                            "--cache-type-k", "q8_0", "--cache-type-v", "q8_0", "-lv", "4"] + serverArguments
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
            if await healthy() == true {
                gpuWarning = await gpuCheck()
                return
            }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
        await stop()
        throw NoteError.notReady("\(label) didn't finish loading within \(Int(loadTimeout))s.")
    }

    /// A warning when the model just loaded takes more GPU memory than
    /// macOS lets one program use (Metal's recommendedMaxWorkingSetSize):
    /// past that a draft can fail. Over total memory it would only be
    /// slow, which isn't warned of here. Both figures are from the log.
    private func gpuCheck() async -> String? {
        // The figures are logged before the server answers, but may not
        // have been read yet.
        for _ in 0..<10 where log.gpuUse == nil { await Self.wait(milliseconds: 50) }
        guard let use = log.gpuUse, use.buffers > use.budget else { return nil }
        func gb(_ mib: Double) -> String { String(format: "%.1f GB", mib * 1_048_576 / 1e9) }
        let instead = lighter.map { " \($0) needs less." } ?? " Closing other apps won't help; a shorter session might."
        return "\(label) took \(gb(use.buffers)) of GPU memory for this note, more than the \(gb(use.budget)) this Mac allows one app, so drafting may fail.\(instead)"
    }

    public func loadWarnings() async -> [String] { gpuWarning.map { [$0] } ?? [] }

    /// One chat request to the running server. Thinking is always off: with
    /// it on a note takes many minutes longer, and the prompts were tested
    /// without it. The server doesn't stream here, so `tokens` is not called.
    public func request(prompt: String, cap: Int, schema: Data?, tokens: @escaping @Sendable (Int) -> Void) async throws -> ModelReply {
        if let fault { throw fault }
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
            throw await failure("The request to \(label) failed: \(error.localizedDescription)")
        }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = reply["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? "\(error)"
            throw await failure("\(label) error: \(message)")
        }
        let choice = (reply["choices"] as? [[String: Any]])?.first
        let text = (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw NoteError.requestFailed("\(label) returned no content.") }
        return ModelReply(text: text, cutOff: choice?["finish_reason"] as? String == "length")
    }

    /// What a failed request means. When the GPU ran out of memory the
    /// server is left unable to compute anything until it is restarted
    /// (the engine's Metal backend keeps the error), so it is stopped.
    private func failure(_ message: String) async -> NoteError {
        // The server replies before its log line about the failure may
        // have been read.
        for _ in 0..<10 where !log.sawGPUFailure { await Self.wait(milliseconds: 50) }
        guard log.sawGPUFailure else { return .requestFailed(message) }
        await stop()
        let instead = lighter.map { "Choose \($0) in Settings, which needs less, or close other apps and draft again." }
            ?? "Close other apps and draft again."
        let fault = NoteError.requestFailed("\(label) ran out of GPU memory. \(instead)")
        self.fault = fault
        return fault
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

/// Keeps the last part of a process's output in memory, for an error
/// message, and notes what it says about the GPU as it passes. Nothing is
/// written to disk.
final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    /// The start of a line not yet ended.
    private var partial = ""
    private var gpuFailed = false
    private var budget: Double?
    private var buffers = 0.0

    func follow(_ pipe: Pipe) {
        lock.withLock { text = ""; partial = ""; gpuFailed = false; budget = nil; buffers = 0 }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.add(String(decoding: data, as: UTF8.self))
        }
    }

    func add(_ chunk: String) {
        lock.withLock {
            text += chunk
            if text.count > 2000 { text = String(text.suffix(2000)) }
            var lines = (partial + chunk).split(separator: "\n", omittingEmptySubsequences: false)
            partial = String(lines.removeLast())
            for line in lines {
                if Self.isGPUFailure(line) { gpuFailed = true }
                if let total = Self.gpuBudget(line) { budget = total }
                if let size = Self.gpuBuffer(line) { buffers += size }
            }
        }
    }

    /// A Metal command buffer failed, which on these Macs means the GPU ran
    /// out of memory; every later computation then fails as well.
    static func isGPUFailure(_ line: Substring) -> Bool {
        line.contains("failed with status") && line.contains("command buffer")
            || line.contains("error state from a previous command buffer failure")
    }

    /// The GPU's memory in MiB, from the device list logged at startup:
    /// `- MTL0    : Apple M4 (12124 MiB, 12123 MiB free)`. On a Mac this is
    /// Metal's recommendedMaxWorkingSetSize.
    static func gpuBudget(_ line: Substring) -> Double? {
        guard let m = line.firstMatch(of: /- MTL0\s*: .*\((\d+) MiB, \d+ MiB free\)/) else { return nil }
        return Double(m.1)
    }

    /// The size in MiB of one buffer the model put on the GPU: its weights,
    /// KV cache or compute buffer, as
    /// `MTL0_Mapped model buffer size =  4731.51 MiB`.
    static func gpuBuffer(_ line: Substring) -> Double? {
        guard let m = line.firstMatch(of: /\sMTL0\S*\s+.*buffer size\s*=\s*([\d.]+) MiB/) else { return nil }
        return Double(m.1)
    }

    var sawGPUFailure: Bool { lock.withLock { gpuFailed } }

    /// What the server has put on the GPU and what the GPU allows, in MiB,
    /// once both have been logged.
    var gpuUse: (buffers: Double, budget: Double)? {
        lock.withLock { budget.flatMap { buffers > 0 ? (buffers, $0) : nil } }
    }

    /// The last five lines.
    var tail: String {
        lock.withLock { text.split(separator: "\n").suffix(5).joined(separator: "\n") }
    }
}
