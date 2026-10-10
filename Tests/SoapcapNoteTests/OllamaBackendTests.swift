import XCTest
@testable import SoapcapNote

/// Answers URLSession requests from a table, recording what was sent.
final class StubHTTP: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [String: String] = [:]   // path -> body
    /// Asked first; nil falls through to `replies`.
    nonisolated(unsafe) static var answer: (String) -> String? = { _ in nil }
    nonisolated(unsafe) static var sent: [(path: String, body: [String: Any])] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTP.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let path = request.url!.path
        Self.sent.append((path, body))
        guard let reply = Self.answer(path) ?? Self.replies[path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class OllamaBackendTests: XCTestCase {
    override func setUp() { StubHTTP.replies = [:]; StubHTTP.sent = []; StubHTTP.answer = { _ in nil } }

    private func backend(_ model: String = "llama3.1:8b", host: String = "http://localhost:11434") -> OllamaBackend {
        OllamaBackend(model: model, host: URL(string: host)!, session: StubHTTP.session())
    }

    func testCheckSaysWhatToDoWhenOllamaIsDownOrTheModelIsMissing() async {
        do { try await backend().check(); XCTFail("ready") } catch {
            XCTAssertTrue(error.localizedDescription.contains("brew services start ollama"), error.localizedDescription)
        }
        StubHTTP.replies["/api/tags"] = #"{"models": [{"name": "qwen3:14b"}]}"#
        do { try await backend().check(); XCTFail("ready") } catch {
            XCTAssertTrue(error.localizedDescription.contains("ollama pull llama3.1:8b"), error.localizedDescription)
        }
    }

    func testAModelMatchesByTagOrByNameWithoutItsSize() async throws {
        StubHTTP.replies["/api/tags"] = #"{"models": [{"name": "llama3.1:8b"}]}"#
        try await backend().check()
        try await backend("llama3.1").check()
        XCTAssertFalse(OllamaBackend.has("llama3", in: ["llama3.1:8b"]))
    }

    func testAProseRequestStreamsTokensWithTheNarrativeSettings() async throws {
        StubHTTP.replies["/api/tags"] = #"{"models": [{"name": "llama3.1:8b"}]}"#
        StubHTTP.replies["/api/generate"] = """
        {"response": "SUBJECTIVE:", "done": false}
        {"response": "\\nSlept badly.", "done": false}
        {"response": "", "done": true, "done_reason": "stop"}

        """
        let ollama = backend()
        try await ollama.start(context: 9216)
        let seen = Seen()
        let reply = try await ollama.request(prompt: "PROMPT", cap: 2000, schema: nil) { seen.add(DraftProgress(title: "", tokens: $0)) }
        XCTAssertEqual(reply, ModelReply(text: "SUBJECTIVE:\nSlept badly.", cutOff: false))
        XCTAssertEqual(seen.all.compactMap(\.tokens), [1, 2])
        let sent = StubHTTP.sent.last!.body
        XCTAssertEqual(sent["model"] as? String, "llama3.1:8b")
        XCTAssertEqual(sent["prompt"] as? String, "PROMPT")
        XCTAssertEqual(sent["think"] as? Bool, false)
        XCTAssertEqual(sent["stream"] as? Bool, true)
        XCTAssertNil(sent["format"])
        let options = sent["options"] as? [String: Any] ?? [:]
        XCTAssertEqual(options["num_ctx"] as? Int, 9216)
        XCTAssertEqual(options["num_predict"] as? Int, 2000)
        XCTAssertEqual(options["temperature"] as? Double, 0.7)
        XCTAssertEqual(options["top_p"] as? Double, 0.8)
        XCTAssertEqual(options["top_k"] as? Int, 20)
    }

    func testASchemaRequestSendsTheSchemaAndTheStructuredTemperature() async throws {
        StubHTTP.replies["/api/tags"] = #"{"models": [{"name": "llama3.1:8b"}]}"#
        StubHTTP.replies["/api/generate"] = #"{"response": "{}", "done": true, "done_reason": "length"}"#
        let ollama = backend()
        try await ollama.start(context: 100)
        let reply = try await ollama.request(prompt: "P", cap: 600, schema: try Prompts.objectiveSchema()) { _ in }
        XCTAssertTrue(reply.cutOff)
        let sent = StubHTTP.sent.last!.body
        XCTAssertEqual((sent["format"] as? [String: Any])?["required"] as? [String], ["mental_status", "risk", "risk_kind"])
        let options = sent["options"] as? [String: Any] ?? [:]
        XCTAssertEqual(options["temperature"] as? Double, 0.3)
        XCTAssertEqual(options["num_ctx"] as? Int, 4096, "never below 4096")
    }

    func testAnOllamaErrorOrAnEmptyReplyIsAFailure() async {
        StubHTTP.replies["/api/generate"] = #"{"error": "model requires more system memory"}"#
        do { _ = try await backend().request(prompt: "P", cap: 10, schema: nil) { _ in }; XCTFail("replied") } catch {
            XCTAssertEqual(error as? NoteError, .requestFailed("Ollama error: model requires more system memory"))
        }
        StubHTTP.replies["/api/generate"] = #"{"response": "", "done": true, "done_reason": "stop"}"#
        do { _ = try await backend().request(prompt: "P", cap: 10, schema: nil) { _ in }; XCTFail("replied") } catch {
            XCTAssertEqual(error as? NoteError, .requestFailed("Ollama returned no content."))
        }
    }

    func testStopAsksOllamaToUnloadTheModel() async {
        StubHTTP.replies["/api/generate"] = "{}"
        await backend().stop()
        XCTAssertEqual(StubHTTP.sent.last?.body["keep_alive"] as? Int, 0)
        XCTAssertEqual(StubHTTP.sent.last?.body["model"] as? String, "llama3.1:8b")
    }

    func testCautionsCoverAnUntestedModelAndAHostThatIsNotThisMac() {
        XCTAssertEqual(backend().cautions, [])
        XCTAssertEqual(backend("qwen3:14b").cautions.count, 1)
        XCTAssertEqual(backend(host: "http://192.168.1.20:11434").cautions.count, 1)
        XCTAssertTrue(OllamaBackend.isLocal(URL(string: "http://127.0.0.1:11434")!))
        XCTAssertTrue(OllamaBackend.isLocal(URL(string: "http://[::1]:11434")!))
        XCTAssertFalse(OllamaBackend.isLocal(URL(string: "http://nas.lan:11434")!))
    }
}
