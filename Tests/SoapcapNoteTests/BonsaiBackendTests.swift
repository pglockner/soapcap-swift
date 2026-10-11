import XCTest
@testable import SoapcapNote

/// A stand-in llama-server, as in soapcap's tests: notes the key it was
/// given, logs its arguments, then runs until signalled. With the `crash` file present it exits at once, as a
/// failed model load does; with `stubborn` it ignores a polite stop.
private let fakeServer = #"""
#!/usr/bin/env bash
dir=$(dirname "$0")
if [ -f "$dir/crash" ]; then echo "llama_model_load: error loading model" >&2; exit 1; fi
echo "$LLAMA_API_KEY" > "$dir/key"
echo "started $*" >> "$dir/log"
if [ -f "$dir/stubborn" ]; then trap '' TERM; else trap 'echo stopped >> "$dir/log"; exit 0' TERM INT; fi
while :; do sleep 0.05; done
"""#

final class BonsaiBackendTests: XCTestCase {
    private var dir: URL!
    private var install: BonsaiBackend.Install!

    override func setUpWithError() throws {
        StubHTTP.replies = [:]; StubHTTP.sent = []; StubHTTP.answer = { _ in nil }
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("soapcap-bonsai-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let server = dir.appendingPathComponent("llama-server"), weights = dir.appendingPathComponent("model.gguf")
        try fakeServer.write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        try Data().write(to: weights)
        install = .init(server: server, weights: weights, port: 18999)
        // The server "answers" once it has started, like a model that has loaded.
        let log = dir.appendingPathComponent("log").path
        StubHTTP.answer = { path in
            let lines = ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n")
            return path == "/health" && lines.last?.hasPrefix("started") == true ? #"{"status": "ok"}"# : nil
        }
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func backend() -> BonsaiBackend {
        BonsaiBackend(install: install, session: StubHTTP.session(), loadTimeout: 5, pollInterval: 0.05)
    }

    private var log: [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    private func touch(_ name: String) { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: nil) }

    func testCheckSaysWhenBonsaiIsNotSetUpOrThePortIsTaken() async throws {
        try await backend().check()
        StubHTTP.answer = { _ in #"{"status": "ok"}"# }
        do { try await backend().check(); XCTFail("ready") } catch {
            XCTAssertTrue(error.localizedDescription.contains("already listening on port 18999"), error.localizedDescription)
        }
        try FileManager.default.removeItem(at: install.weights)
        do { try await backend().check(); XCTFail("ready") } catch {
            XCTAssertTrue(error.localizedDescription.contains("isn't set up"), error.localizedDescription)
        }
    }

    func testStartLaunchesTheServerWithSoapcapsFlagsAndStopEndsIt() async throws {
        let bonsai = backend()
        try await bonsai.start(context: 100)
        XCTAssertEqual(log, ["started -m \(install.weights.path) --host 127.0.0.1 --port 18999 -ngl 99 -c 8192 --parallel 1 --cache-type-k q8_0 --cache-type-v q8_0"])
        await bonsai.stop()
        XCTAssertEqual(log.last, "stopped")
        await bonsai.stop()
    }

    func testARunningServerIsReusedUnlessTheContextMustGrow() async throws {
        let bonsai = backend()
        try await bonsai.start(context: 12288)
        try await bonsai.start(context: 9000)
        XCTAssertEqual(log.count, 1)
        try await bonsai.start(context: 16384)
        XCTAssertEqual(log.count, 3, "\(log)")
        XCTAssertEqual(log[1], "stopped")
        XCTAssertTrue(log[2].contains("-c 16384"), "\(log)")
        await bonsai.stop()
    }

    func testAServerThatDiesWhileLoadingReportsItsLastLines() async {
        touch("crash")
        do { try await backend().start(context: 8192); XCTFail("started") } catch {
            XCTAssertTrue(error.localizedDescription.contains("error loading model"), error.localizedDescription)
        }
    }

    func testOnlyTheAppCanTalkToTheServerItStarts() async throws {
        StubHTTP.replies["/v1/chat/completions"] = #"{"choices": [{"message": {"content": "ok"}, "finish_reason": "stop"}]}"#
        let bonsai = backend()
        func key() throws -> String {
            try String(contentsOf: dir.appendingPathComponent("key"), encoding: .utf8).trimmingCharacters(in: .newlines)
        }
        try await bonsai.start(context: 8192)
        let first = try key()
        XCTAssertEqual(first.count, 64)
        XCTAssertFalse(log.joined().contains(first), "the key must not be on the command line")
        _ = try await bonsai.request(prompt: "P", cap: 10, schema: nil) { _ in }
        XCTAssertEqual(StubHTTP.sent.last?.authorization, "Bearer \(first)")
        await bonsai.stop()
        try await bonsai.start(context: 8192)
        XCTAssertNotEqual(try key(), first, "each server gets a key of its own")
        await bonsai.stop()
    }

    func testGivingUpWhileTheModelLoadsStopsTheServer() async throws {
        StubHTTP.answer = { _ in nil }                       // a model that never finishes loading
        let bonsai = backend()
        let loading = Task { try await bonsai.start(context: 8192) }
        for _ in 0..<100 where log.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(log.count, 1, "\(log)")
        loading.cancel()
        do { try await loading.value; XCTFail("loaded") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertEqual(log.last, "stopped")

        // Given up on before it began: nothing is started at all.
        let never = Task {
            try? await Task.sleep(for: .seconds(5))          // ends as soon as the task is cancelled
            try await bonsai.start(context: 8192)
        }
        never.cancel()
        do { try await never.value; XCTFail("started") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertEqual(log.count, 2, "\(log)")
    }

    func testAServerThatIgnoresAPoliteStopIsKilled() async throws {
        touch("stubborn")
        let bonsai = backend()
        try await bonsai.start(context: 8192)
        let began = Date()
        await bonsai.stop()
        XCTAssertGreaterThan(Date().timeIntervalSince(began), 2.5)
        let left = Process()
        left.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        left.arguments = ["-f", install.server.path]
        left.standardOutput = FileHandle.nullDevice
        try left.run(); left.waitUntilExit()
        XCTAssertEqual(left.terminationStatus, 1, "the server is still running")
    }

    func testARequestSendsSoapcapsSettingsAndReadsTheReply() async throws {
        StubHTTP.replies["/v1/chat/completions"] = #"{"choices": [{"message": {"content": "PLAN:\nWeekly."}, "finish_reason": "length"}]}"#
        let reply = try await backend().request(prompt: "PROMPT", cap: 2000, schema: nil) { _ in }
        XCTAssertEqual(reply, ModelReply(text: "PLAN:\nWeekly.", cutOff: true))
        let sent = StubHTTP.sent.last!.body
        XCTAssertEqual((sent["messages"] as? [[String: String]])?.first, ["role": "user", "content": "PROMPT"])
        XCTAssertEqual((sent["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"], false)
        XCTAssertEqual(sent["max_tokens"] as? Int, 2000)
        XCTAssertEqual(sent["temperature"] as? Double, 0.7)
        XCTAssertEqual(sent["stream"] as? Bool, false)
        XCTAssertNil(sent["response_format"])

        StubHTTP.replies["/v1/chat/completions"] = #"{"choices": [{"message": {"content": "{}"}, "finish_reason": "stop"}]}"#
        _ = try await backend().request(prompt: "P", cap: 600, schema: try Prompts.objectiveSchema()) { _ in }
        let structured = StubHTTP.sent.last!.body
        XCTAssertEqual(structured["temperature"] as? Double, 0.3)
        XCTAssertEqual((structured["response_format"] as? [String: Any])?["type"] as? String, "json_schema")
    }

    func testAServerErrorOrAnEmptyReplyIsAFailure() async {
        StubHTTP.replies["/v1/chat/completions"] = #"{"error": {"message": "context too small"}}"#
        do { _ = try await backend().request(prompt: "P", cap: 10, schema: nil) { _ in }; XCTFail("replied") } catch {
            XCTAssertEqual(error as? NoteError, .requestFailed("Bonsai error: context too small"))
        }
        StubHTTP.replies["/v1/chat/completions"] = #"{"choices": []}"#
        do { _ = try await backend().request(prompt: "P", cap: 10, schema: nil) { _ in }; XCTFail("replied") } catch {
            XCTAssertEqual(error as? NoteError, .requestFailed("Bonsai returned no content."))
        }
    }
}
