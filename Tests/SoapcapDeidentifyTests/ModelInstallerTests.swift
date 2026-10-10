import XCTest
@testable import SoapcapDeidentify

/// Serves files by URL path, recording what was asked for.
private final class StubDownloads: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [String: Data] = [:]
    nonisolated(unsafe) static var asked: [String] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubDownloads.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path
        Self.asked.append(path)
        let body = Self.bodies[path]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data("Not Found".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class ModelInstallerTests: XCTestCase {
    private var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "soapcap-model-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        StubDownloads.bodies = [:]
        StubDownloads.asked = []
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private var directory: URL { root.appending(path: "app/deidentify-model") }

    private func installer(_ files: [ModelFile]) -> ModelInstaller {
        var installer = ModelInstaller()
        installer.files = files
        installer.directory = directory
        installer.soapcapModels = root.appending(path: "soapcap/models")
        installer.session = StubDownloads.session()
        try? FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        return installer
    }

    private func file(_ name: String, _ body: String, cache: String = "openmed") throws -> ModelFile {
        let scratch = root.appending(path: "hash-\(name)")
        try Data(body.utf8).write(to: scratch)
        return ModelFile(name, repo: "Org/Model", revision: "abc", sha256: try ModelInstaller.sha256(of: scratch), soapcapCache: cache)
    }

    private func leftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)) ?? []).sorted()
    }

    func testFilesAreDownloadedFromTheirPinnedRevisionAndChecked() async throws {
        let files = [try file("weights.bin", "weights"), try file("tokenizer.json", "{}")]
        StubDownloads.bodies = ["/Org/Model/resolve/abc/weights.bin": Data("weights".utf8), "/Org/Model/resolve/abc/tokenizer.json": Data("{}".utf8)]
        XCTAssertFalse(ModelFiles.isReady(in: directory, files: files))
        let source = try await installer(files).install()
        XCTAssertEqual(source, .download)
        XCTAssertTrue(ModelFiles.isReady(in: directory, files: files))
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "weights.bin"), encoding: .utf8), "weights")
        XCTAssertEqual(leftovers(), ["deidentify-model"])
    }

    func testAFileWithTheWrongChecksumIsRejectedAndNothingIsLeftBehind() async throws {
        let files = [try file("tokenizer.json", "{}"), try file("weights.bin", "weights")]
        StubDownloads.bodies = ["/Org/Model/resolve/abc/tokenizer.json": Data("{}".utf8), "/Org/Model/resolve/abc/weights.bin": Data("tampered".utf8)]
        do { try await installer(files).install(); XCTFail("installed") } catch {
            XCTAssertEqual(error as? ModelInstallError, .checksum(file: "weights.bin"))
        }
        XCTAssertFalse(ModelFiles.isReady(in: directory, files: files))
        XCTAssertEqual(leftovers(), [])
    }

    func testAMissingFileUpstreamIsAnErrorNotAnInstalledErrorPage() async throws {
        let files = [try file("weights.bin", "Not Found")]
        do { try await installer(files).install(); XCTFail("installed") } catch {
            XCTAssertEqual(error as? ModelInstallError, .download(file: "weights.bin", detail: "the server answered 404"))
        }
        XCTAssertEqual(leftovers(), [])
    }

    func testSoapcapsCopyIsUsedWithoutTheNetwork() async throws {
        let files = [try file("weights.bin", "weights"), try file("tokenizer.json", "{}", cache: "hub")]
        let made = installer(files)
        XCTAssertFalse(made.canCopyFromSoapcap)
        for f in files {
            let copy = f.soapcapCopy(in: made.soapcapModels)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((f.name == "weights.bin" ? "weights" : "{}").utf8).write(to: copy)
        }
        XCTAssertTrue(made.canCopyFromSoapcap)
        XCTAssertTrue(files[1].soapcapCopy(in: made.soapcapModels).path.hasSuffix("soapcap/models/hub/models--Org--Model/snapshots/abc/tokenizer.json"))
        let source = try await made.install()
        XCTAssertEqual(source, .soapcap)
        XCTAssertEqual(StubDownloads.asked, [])
        XCTAssertTrue(ModelFiles.isReady(in: directory, files: files))
    }

    func testASoapcapCopyThatFailsItsChecksumIsDownloadedInstead() async throws {
        let files = [try file("weights.bin", "weights")]
        let made = installer(files)
        let copy = files[0].soapcapCopy(in: made.soapcapModels)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("older weights".utf8).write(to: copy)
        StubDownloads.bodies = ["/Org/Model/resolve/abc/weights.bin": Data("weights".utf8)]
        let source = try await made.install()
        XCTAssertEqual(source, .download)
        XCTAssertEqual(StubDownloads.asked, ["/Org/Model/resolve/abc/weights.bin"])
    }

    func testInstallingAgainReplacesWhatWasThere() async throws {
        let files = [try file("weights.bin", "weights")]
        StubDownloads.bodies = ["/Org/Model/resolve/abc/weights.bin": Data("weights".utf8)]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: directory.appending(path: "old-file"))
        try await installer(files).install()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["weights.bin"])
    }

    func testThePinnedFilesAreTheSixTheModelNeeds() {
        XCTAssertEqual(ModelFiles.pinned.map(\.name).sorted(),
                       ["config.json", "id2label.json", "special_tokens_map.json", "tokenizer.json", "tokenizer_config.json", "weights.safetensors"])
        XCTAssertTrue(ModelFiles.pinned.allSatisfy { $0.sha256.count == 64 && $0.url.absoluteString.contains("/resolve/\($0.revision)/") })
    }
}
