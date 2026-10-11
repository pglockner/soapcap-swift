import SoapcapCore
import XCTest
@testable import SoapcapUI

@MainActor
final class ModelDownloadTests: XCTestCase {
    private var root: URL!
    private let file = PinnedFile(name: "model.gguf", url: URL(string: "https://example.com/model.gguf")!, sha256: "abc", bytes: 1000)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "soapcap-download-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private var target: URL { root.appending(path: "mine/model.gguf") }
    private var soapcaps: URL { root.appending(path: "soapcap/model.gguf") }

    private func write(_ url: URL, _ text: String = "weights") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A fetch that reports halfway, waits, then does what `end` says.
    private func download(_ end: @escaping @Sendable (URL) throws -> Void) -> ModelDownload {
        ModelDownload(file: file, target: target, elsewhere: soapcaps) { file, target, progress in
            progress(FetchProgress(bytes: 500, total: file.bytes, bytesPerSecond: 100))
            try await Task.sleep(for: .milliseconds(150))
            try end(target)
        }
    }

    func testADownloadGoesFromMissingThroughProgressToReady() async throws {
        let target = target
        let download = download { _ in
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: target)
        }
        XCTAssertEqual(download.state, .missing)
        XCTAssertFalse(download.isInstalled)
        download.start()
        await waitFor("progress") { download.state == .working(FetchProgress(bytes: 500, total: 1000, bytesPerSecond: 100)) }
        await waitFor("ready") { download.state == .ready }
        XCTAssertTrue(download.isInstalled)
    }

    func testAFailureSaysWhyAndCanBeTriedAgain() async {
        let download = download { _ in throw FetchError.download(file: "model.gguf", detail: "the server answered 503") }
        download.start()
        await waitFor("failed") { download.state == .failed("Couldn't download model.gguf: the server answered 503") }
        download.start()
        await waitFor("working again") { if case .working = download.state { true } else { false } }
    }

    func testStoppingKeepsWhatArrivedAndIsNotAFailure() async throws {
        let download = download { _ in }
        try write(Fetcher.part(of: target), "half")
        download.start()
        await waitFor("working") { if case .working = download.state { true } else { false } }
        download.stop()
        await waitFor("stopped") { download.state == .missing }
        XCTAssertEqual(download.keptBytes, 4)
    }

    func testACopySomethingElseInstalledIsUsedAndNeverRemoved() throws {
        try write(soapcaps)
        let download = download { _ in }
        XCTAssertEqual(download.state, .elsewhere)
        XCTAssertTrue(download.isInstalled)
        download.remove()
        XCTAssertTrue(FileManager.default.fileExists(atPath: soapcaps.path))
        XCTAssertEqual(download.state, .elsewhere)
    }

    func testRemovingDeletesTheAppsCopyAndWhatAStoppedDownloadLeft() throws {
        try write(target)
        try write(Fetcher.part(of: target), "half")
        let download = download { _ in }
        XCTAssertEqual(download.state, .ready)
        download.remove()
        XCTAssertEqual(download.state, .missing)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) ?? [], [])
    }
}
