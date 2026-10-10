import Foundation

/// Any model pulled into Ollama, over its HTTP API.
public actor OllamaBackend: NoteBackend {
    public static let defaultHost = URL(string: "http://localhost:11434")!
    /// The models soapcap's prompts were tested with.
    public static let tested = ["llama3.1:8b"]

    public nonisolated let model: String
    public nonisolated let host: URL
    private let session: URLSession
    private var context = 4096

    public init(model: String, host: URL = OllamaBackend.defaultHost, session: URLSession = .shared) {
        self.model = model
        self.host = host
        self.session = session
    }

    public nonisolated var label: String { model }

    public nonisolated var cautions: [String] {
        var out: [String] = []
        if !Self.tested.contains(model) {
            out.append("\(model) hasn't been tested with soapcap's prompts — proofread it with extra care.")
        }
        if !Self.isLocal(host) {
            out.append("\(host.absoluteString) is not this Mac — the transcript was sent to that machine over the network.")
        }
        return out
    }

    /// The promise is that a transcript never leaves this Mac; the host setting can break it.
    public static func isLocal(_ host: URL) -> Bool {
        guard let name = host.host() else { return false }
        return name == "localhost" || name.hasPrefix("127.") || name == "::1" || name == "[::1]"
    }

    /// The tags pulled into this Ollama. Throws when nothing answers.
    public func models() async throws -> [String] {
        struct Tags: Decodable { struct Model: Decodable { var name: String }; var models: [Model]? }
        var request = URLRequest(url: host.appendingPathComponent("api/tags"))
        request.timeoutInterval = 5
        do {
            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(Tags.self, from: data).models?.map(\.name) ?? []
        } catch {
            throw NoteError.notReady("Can't reach Ollama at \(host.absoluteString). Start it with: brew services start ollama (or: ollama serve)")
        }
    }

    /// Is `model` among `tags`, or does it name one without its size ("llama3.1")?
    public static func has(_ model: String, in tags: [String]) -> Bool {
        tags.contains { $0 == model || $0.hasPrefix(model + ":") }
    }

    public func check() async throws {
        guard Self.has(model, in: try await models()) else {
            throw NoteError.notReady("The model '\(model)' is not pulled. Run: ollama pull \(model)")
        }
    }

    /// Ollama loads a model on its first request and again whenever a
    /// request's context size differs from the last, so every pass of a note
    /// sends this one size. Never below 4096: its own default is far too small.
    public func start(context: Int) async throws {
        try await check()
        self.context = max(context, 4096)
    }

    /// Prose under the narrative sampling settings, or JSON matching `schema`
    /// under the structured ones: the settings soapcap's prompts were tested
    /// with. Thinking is off: reasoning made notes worse in testing.
    public func request(prompt: String, cap: Int, schema: Data?, tokens: @escaping @Sendable (Int) -> Void) async throws -> ModelReply {
        var options: [String: Any] = ["num_ctx": context, "num_predict": cap, "top_p": 0.8, "top_k": 20]
        options["temperature"] = schema == nil ? 0.7 : 0.3
        var body: [String: Any] = ["model": model, "prompt": prompt, "stream": true, "think": false, "options": options]
        if let schema { body["format"] = try JSONSerialization.jsonObject(with: schema) }

        var request = URLRequest(url: host.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        struct Chunk: Decodable { var response: String?; var done_reason: String?; var error: String? }
        var text = "", reason = "", count = 0
        do {
            let (bytes, _) = try await session.bytes(for: request)
            for try await line in bytes.lines {
                guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
                if let error = chunk.error { throw NoteError.requestFailed("Ollama error: \(error)") }
                if let piece = chunk.response, !piece.isEmpty {
                    text += piece
                    count += 1
                    tokens(count)
                }
                if let done = chunk.done_reason { reason = done }
            }
        } catch let error as NoteError {
            throw error
        } catch {
            throw NoteError.requestFailed("The request to Ollama failed: \(error.localizedDescription)")
        }
        guard !text.isEmpty else { throw NoteError.requestFailed("Ollama returned no content.") }
        return ModelReply(text: text, cutOff: reason == "length")
    }

    /// Asks Ollama to unload the model now rather than hold it for its
    /// default five minutes. Best effort.
    public func stop() async {
        var request = URLRequest(url: host.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
    }
}
