import XCTest
@testable import SoapcapUI

final class UninstallerTests: XCTestCase {
    private var library: URL!

    override func setUp() {
        library = FileManager.default.temporaryDirectory.appending(path: "soapcap-uninstall-tests-\(UUID().uuidString)/Library")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: library.deletingLastPathComponent()) }

    private func write(_ path: String, bytes: Int = 10) throws -> URL {
        let url = library.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func testItRemovesWhatTheAppPutThereAndNothingElse() throws {
        let uninstaller = Uninstaller(bundleID: "test.soapcap", library: library, app: library.appending(path: "Soapcap.app"))
        XCTAssertEqual(uninstaller.leftovers, [])
        XCTAssertEqual(uninstaller.bytes, 0)

        let bonsai = try write("Application Support/Soapcap/note-models/bonsai.gguf", bytes: 3000)
        let pii = try write("Application Support/Soapcap/deidentify-model/weights.safetensors", bytes: 500)
        let cache = try write("Caches/test.soapcap/Cache.db", bytes: 40)
        let state = try write("Saved Application State/test.soapcap.savedState/windows.plist", bytes: 2)
        // Not the app's: another app's support folder, and another app's cache.
        let others = [try write("Application Support/Ollama/models/blob"), try write("Caches/com.example.other/Cache.db")]

        XCTAssertEqual(uninstaller.leftovers.count, 3)
        XCTAssertEqual(uninstaller.bytes, 3542)
        XCTAssertTrue(uninstaller.summary.contains("then moves Soapcap to the Trash"))
        XCTAssertEqual(uninstaller.removeData(), [])
        for gone in [bonsai, pii, cache, state] { XCTAssertFalse(FileManager.default.fileExists(atPath: gone.path), gone.path) }
        for kept in others { XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), kept.path) }
        XCTAssertEqual(uninstaller.leftovers, [])
    }
}
