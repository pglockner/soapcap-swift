import XCTest
@testable import SoapcapCore

/// Serves one file, as a server that can be asked for the rest of it.
private final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    /// The Range header of each request, in order.
    nonisolated(unsafe) static var ranges: [String?] = []
    /// Send this many bytes of the next reply, then drop the connection.
    nonisolated(unsafe) static var cutAfter: Int?
    nonisolated(unsafe) static var honoursRange = true
    nonisolated(unsafe) static var status: Int?

    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        Self.ranges.append(range)
        func answer(_ status: Int) {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                                                 headerFields: ["Content-Type": "application/octet-stream"])!,
                                cacheStoragePolicy: .notAllowed)
        }
        if let status = Self.status {
            answer(status)
            client?.urlProtocol(self, didLoad: Data("Not Found".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var start = 0
        if Self.honoursRange, let range, let asked = Int(range.dropFirst("bytes=".count).dropLast()) { start = asked }
        let reply = Self.body.subdata(in: start..<Self.body.count)
        answer(start > 0 ? 206 : 200)
        if let cut = Self.cutAfter {
            Self.cutAfter = nil
            client?.urlProtocol(self, didLoad: reply.prefix(cut))
            // A moment later, as on a real connection: what arrived has been handed on by then.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class FetcherTests: XCTestCase {
    private var root: URL!
    /// Big enough that URLSession hands it on as it arrives instead of holding the first bytes back.
    private let body = Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "soapcap-fetch-tests-\(UUID().uuidString)")
        StubServer.body = body
        StubServer.ranges = []
        StubServer.cutAfter = nil
        StubServer.honoursRange = true
        StubServer.status = nil
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private var target: URL { root.appending(path: "models/model.gguf") }
    private var fetcher: Fetcher { Fetcher(configuration: StubServer.configuration) }

    private func file(sha256: String? = nil) throws -> PinnedFile {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "soapcap-fetch-hash-\(UUID().uuidString)")
        try body.write(to: scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }
        return PinnedFile(name: "model.gguf", url: URL(string: "https://example.com/model.gguf")!,
                          sha256: try sha256 ?? Fetcher.sha256(of: scratch), bytes: Int64(body.count))
    }

    private func inFolder() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) ?? []).sorted()
    }

    func testAFileIsFetchedCheckedAndPutInPlace() async throws {
        try await fetcher.fetch(try file(), to: target)
        XCTAssertEqual(try Data(contentsOf: target), body)
        XCTAssertEqual(inFolder(), ["model.gguf"])
        XCTAssertEqual(StubServer.ranges, [nil])
    }

    func testAnInterruptedFetchCarriesOnFromWhereItStopped() async throws {
        StubServer.cutAfter = 3000
        do { try await fetcher.fetch(try file(), to: target); XCTFail("fetched") } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Couldn't download model.gguf"), error.localizedDescription)
        }
        XCTAssertEqual(inFolder(), ["model.gguf.part"], "what arrived is kept, and nothing is put in place")
        XCTAssertEqual(Fetcher.size(of: Fetcher.part(of: target)), 3000)
        try await fetcher.fetch(try file(), to: target)
        XCTAssertEqual(StubServer.ranges, [nil, "bytes=3000-"])
        XCTAssertEqual(try Data(contentsOf: target), body)
        XCTAssertEqual(inFolder(), ["model.gguf"])
    }

    func testAServerThatSendsTheWholeFileAgainStartsOver() async throws {
        StubServer.cutAfter = 3000
        _ = try? await fetcher.fetch(try file(), to: target)
        XCTAssertEqual(Fetcher.size(of: Fetcher.part(of: target)), 3000)
        StubServer.honoursRange = false
        try await fetcher.fetch(try file(), to: target)
        XCTAssertEqual(try Data(contentsOf: target), body)
    }

    func testAFileThatFailsItsChecksumIsDiscarded() async throws {
        do { try await fetcher.fetch(try file(sha256: "0000"), to: target); XCTFail("fetched") } catch {
            XCTAssertEqual(error as? FetchError, .checksum(file: "model.gguf"))
        }
        XCTAssertEqual(inFolder(), [])
    }

    func testAnErrorPageIsNotMistakenForTheFile() async throws {
        StubServer.status = 404
        do { try await fetcher.fetch(try file(), to: target); XCTFail("fetched") } catch {
            XCTAssertEqual(error as? FetchError, .download(file: "model.gguf", detail: "the server answered 404"))
        }
        XCTAssertEqual(inFolder(), [])
    }

    func testTooLittleDiskIsSaidBeforeAnythingIsFetched() async throws {
        var short = fetcher
        short.freeBytes = { _ in 10 }
        do { try await short.fetch(try file(), to: target); XCTFail("fetched") } catch {
            XCTAssertEqual(error as? FetchError, .noRoom(file: "model.gguf", needBytes: Int64(body.count), freeBytes: 10))
        }
        XCTAssertEqual(StubServer.ranges, [])
    }

    func testFetchingAgainReplacesWhatWasThere() async throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: target)
        try await fetcher.fetch(try file(), to: target)
        XCTAssertEqual(try Data(contentsOf: target), body)
    }

    func testProgressSaysHowMuchHowFastAndHowLong() {
        XCTAssertEqual(FetchProgress(bytes: 2_100_000_000, total: 5_946_648_928, bytesPerSecond: 24_000_000).summary,
                       "2.1 GB of 5.9 GB, 24 MB a second, about 3 minutes left")
        XCTAssertEqual(FetchProgress(bytes: 5_900_000_000, total: 5_946_648_928, bytesPerSecond: 24_000_000).summary,
                       "5.9 GB of 5.9 GB, 24 MB a second, under a minute left")
        XCTAssertEqual(FetchProgress(bytes: 0, total: 130_000_000).summary, "0 MB of 130 MB")
        XCTAssertEqual(FetchProgress(bytes: 1, total: 1, isVerifying: true).summary, "Checking the download…")
        XCTAssertEqual(ByteCount.text(51_000_000_000), "51 GB")
    }
}

/// The real thing, against Hugging Face: stop a fetch partway, then carry
/// on. Only when SOAPCAP_NETWORK_TESTS is set, since it downloads 130 MB.
final class FetcherNetworkTests: XCTestCase {
    func testAStoppedFetchFromHuggingFaceCarriesOn() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOAPCAP_NETWORK_TESTS"] != nil, "set SOAPCAP_NETWORK_TESTS to run")
        let root = FileManager.default.temporaryDirectory.appending(path: "soapcap-fetch-net-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "weights.safetensors")
        let file = PinnedFile(name: "weights.safetensors",
                              url: URL(string: "https://huggingface.co/OpenMed/OpenMed-PII-ClinicalE5-Small-33M-v1-mlx/resolve/593ce409e3ffbe951404f274a0f4459cdf2a421d/weights.safetensors")!,
                              sha256: "87fff672bfae2ee052b0c046b5cbe1bc14792b93eaeca2b2526ac6dd2926cdc9", bytes: 133032689)
        let first = Task { try await Fetcher().fetch(file, to: target) }
        // Let some of it arrive, then stop.
        for _ in 0..<200 where Fetcher.size(of: Fetcher.part(of: target)) < 4_000_000 { try await Task.sleep(for: .milliseconds(50)) }
        first.cancel()
        _ = await first.result
        let kept = Fetcher.size(of: Fetcher.part(of: target))
        XCTAssertGreaterThan(kept, 0)
        XCTAssertLessThan(kept, file.bytes, "the test wants to stop partway; the connection was too fast")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let last = Box()
        try await Fetcher().fetch(file, to: target) { last.progress = $0 }
        XCTAssertEqual(Fetcher.size(of: target), file.bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Fetcher.part(of: target).path))
        XCTAssertEqual(last.progress?.isVerifying, true)
        print("kept \(kept) bytes from the first attempt; resumed and verified")
    }
}

private final class Box: @unchecked Sendable { var progress: FetchProgress? }
