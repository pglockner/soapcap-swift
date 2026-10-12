import SoapcapCore
import XCTest
@testable import SoapcapNote

final class ModelCatalogTests: XCTestCase {
    private let short = MemoryStatus(totalBytes: 16 << 30, freePercent: 41)
    private let roomy = MemoryStatus(totalBytes: 16 << 30, freePercent: 68)

    func testBonsaiHasANameOfItsOwnAndOtherModelsKeepTheirs() {
        XCTAssertEqual(ModelCatalog.displayName(of: "bonsai"), "Bonsai")
        XCTAssertEqual(ModelCatalog.displayName(of: "llama3.1:8b"), "llama3.1:8b")
    }

    func testTheDefaultModelRunsInOllamaWhenOllamaHasItAndOnTheAppsEngineOtherwise() {
        let llama = BonsaiBackend.Install(server: URL(fileURLWithPath: "/nowhere/llama-server"), weights: URL(fileURLWithPath: "/nowhere/llama.gguf"))
        XCTAssertTrue(ModelCatalog.backend(for: "llama3.1:8b", pulled: ["llama3.1:8b"], llama: llama) is OllamaBackend)
        let own = ModelCatalog.backend(for: "llama3.1:8b", pulled: ["qwen3:8b"], llama: llama) as? BonsaiBackend
        XCTAssertEqual(own?.install, llama)
        XCTAssertEqual(own?.label, "llama3.1:8b")
        XCTAssertEqual(own?.resumesFromSharedOpening, false)        // prompts in the order Ollama gets them
        XCTAssertTrue(ModelCatalog.backend(for: "qwen3:8b", pulled: [], llama: llama) is OllamaBackend)   // any other name is Ollama's
        XCTAssertEqual((ModelCatalog.backend(for: "bonsai", pulled: ["llama3.1:8b"], llama: llama) as? BonsaiBackend)?.label, "Bonsai")
    }

    func testWithNeitherOllamaNorItsFileTheDefaultModelPointsAtSettings() async {
        let llama = BonsaiBackend.Install(server: URL(fileURLWithPath: "/nowhere/llama-server"), weights: URL(fileURLWithPath: "/nowhere/llama.gguf"))
        do { try await ModelCatalog.backend(for: "llama3.1:8b", pulled: [], llama: llama).check(); XCTFail("ready") } catch {
            XCTAssertEqual(error.localizedDescription, "llama3.1:8b's model file isn't on this Mac. Get it in Settings (Cmd-comma).")
        }
    }

    func testInstalledNamesTheAppsOwnModelsAndOllamasAndTheDefaultOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "soapcap-catalog-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = root.appending(path: "llama-server"), weights = root.appending(path: "model.gguf")
        try Data("#!/bin/sh\n".utf8).write(to: server)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        try Data("weights".utf8).write(to: weights)
        let here = BonsaiBackend.Install(server: server, weights: weights)
        let missing = BonsaiBackend.Install(server: server, weights: root.appending(path: "none.gguf"))

        XCTAssertEqual(ModelCatalog.installed(pulled: [], bonsai: missing, llama: missing), [])
        XCTAssertEqual(ModelCatalog.installed(pulled: [], bonsai: here, llama: here), ["bonsai", "llama3.1:8b"])
        XCTAssertEqual(ModelCatalog.installed(pulled: ["qwen3:8b", "llama3.1:8b"], bonsai: missing, llama: here), ["llama3.1:8b", "qwen3:8b"])
        XCTAssertEqual(ModelCatalog.installed(pulled: ["qwen3:8b"], bonsai: missing, llama: here), ["llama3.1:8b", "qwen3:8b"])
    }

    func testMemoryAdviceIsOnlyForAModelTheAppLoadsItself() {
        XCTAssertTrue(ModelCatalog.memoryAdvice(for: "bonsai", memory: short)?.hasPrefix("About 6 GB of memory is free and Bonsai takes") == true)
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "bonsai", memory: roomy))
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "llama3.1:8b", memory: short))   // none for it yet, in Ollama or on the app's engine
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "bonsai", memory: nil))
    }

    func testTheMemoryCheckGivesTheFiguresAndWarnsWhenTheModelWontFit() {
        XCTAssertEqual(ModelCatalog.memoryCheck(short, model: "llama3.1:8b"), Check("Memory", .ok, "16 GB, about 6 GB free now."))
        let tight = ModelCatalog.memoryCheck(short, model: "bonsai")
        XCTAssertEqual(tight.status, .warning)
        XCTAssertTrue(tight.detail.hasPrefix("16 GB, about 6 GB free now. About 6 GB of memory is free and Bonsai"), tight.detail)
        XCTAssertEqual(ModelCatalog.memoryCheck(nil, model: "bonsai").status, .warning)
    }
}
