import SoapcapNote
import XCTest
@testable import SoapcapUI

final class UninstallerTests: XCTestCase {
    private var library: URL!
    private var systemCache: URL { library.deletingLastPathComponent().appending(path: "C") }

    override func setUp() {
        library = FileManager.default.temporaryDirectory.appending(path: "soapcap-uninstall-tests-\(UUID().uuidString)/Library")
    }

    private func uninstaller() -> Uninstaller {
        Uninstaller(bundleID: "test.soapcap", library: library, app: library.appending(path: "Soapcap.app"), systemCache: systemCache)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: library.deletingLastPathComponent()) }

    private func write(_ path: String, bytes: Int = 10) throws -> URL {
        let url = library.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func testItRemovesWhatTheAppPutThereAndNothingElse() throws {
        let uninstaller = uninstaller()
        XCTAssertEqual(uninstaller.leftovers, [])
        XCTAssertEqual(uninstaller.bytes, 0)

        let bonsai = try write("Application Support/Soapcap/note-models/bonsai.gguf", bytes: 3000)
        let pii = try write("Application Support/Soapcap/deidentify-model/weights.safetensors", bytes: 500)
        let cache = try write("Caches/test.soapcap/Cache.db", bytes: 40)
        let state = try write("Saved Application State/test.soapcap.savedState/windows.plist", bytes: 2)
        let compiled = try write("../C/test.soapcap/com.apple.metal/functions.data", bytes: 7)
        // Not the app's: another app's support folder, and other apps' caches.
        let others = [try write("Application Support/Ollama/models/blob"), try write("Caches/com.example.other/Cache.db"),
                      try write("../C/com.example.other/com.apple.metal/functions.data")]

        XCTAssertEqual(uninstaller.leftovers.count, 4)
        XCTAssertEqual(uninstaller.bytes, 3500, "the size shown is the models' alone")
        XCTAssertTrue(uninstaller.summary.contains("then moves Soapcap to the Trash"))
        XCTAssertEqual(uninstaller.removeData(), [])
        for gone in [bonsai, pii, cache, state, compiled] { XCTAssertFalse(FileManager.default.fileExists(atPath: gone.path), gone.path) }
        for kept in others { XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), kept.path) }
        XCTAssertEqual(uninstaller.leftovers, [])
    }

    func testRemovingTheCacheTakesAllOfItAndNothingElse() throws {
        let uninstaller = uninstaller()
        uninstaller.removeCache()       // nothing there yet: no harm done

        // What a version that cached a note model's replies left behind.
        let cached = [try write("Caches/test.soapcap/Cache.db"), try write("Caches/test.soapcap/Cache.db-wal"),
                      try write("Caches/test.soapcap/fsCachedData/reply")]
        let kept = [try write("Application Support/Soapcap/note-models/bonsai.gguf"), try write("Caches/com.example.other/Cache.db")]

        uninstaller.removeCache()
        for gone in cached { XCTAssertFalse(FileManager.default.fileExists(atPath: gone.path), gone.path) }
        for there in kept { XCTAssertTrue(FileManager.default.fileExists(atPath: there.path), there.path) }
    }

    func testAfterAnUpgradeARetiredModelAndRetiredSettingsGoAndTheRestStays() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "soapcap-uninstall-tests-\(UUID().uuidString)"))
        defaults.set("http://localhost:11434", forKey: "ollamaHost")
        defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
        let uninstaller = uninstaller()
        uninstaller.removeRetired(defaults: defaults)      // nothing there yet: no harm done

        let retired = try write("Application Support/Soapcap/note-models/Llama-3.1-8B-Instruct-Q4_K_M.gguf")
        let kept = [try write("Application Support/Soapcap/note-models/\(NoteModel.bonsai.weights.name)"),
                    // A download of a model the app offers, stopped part way.
                    try write("Application Support/Soapcap/note-models/\(NoteModel.gemma.weights.name).part"),
                    try write("Application Support/Soapcap/deidentify-model/weights.safetensors")]

        uninstaller.removeRetired(defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retired.path))
        for there in kept { XCTAssertTrue(FileManager.default.fileExists(atPath: there.path), there.path) }
        XCTAssertNil(defaults.object(forKey: "ollamaHost"))
        XCTAssertEqual(defaults.string(forKey: SessionSettings.Key.noteModel), "bonsai")
    }
}
