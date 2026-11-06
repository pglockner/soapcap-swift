import SoapcapCore
import XCTest
@testable import SoapcapNote

final class ModelCatalogTests: XCTestCase {
    private let small = MemoryStatus(totalBytes: 8 << 30, freePercent: 90)
    private let roomy = MemoryStatus(totalBytes: 16 << 30, freePercent: 41)

    func testEachModelHasANameOnScreenAndOtherNamesKeepTheirs() {
        XCTAssertEqual(ModelCatalog.displayName(of: "gemma4-e4b"), "Gemma 4 E4B")
        XCTAssertEqual(ModelCatalog.displayName(of: "bonsai"), "Bonsai")
        XCTAssertEqual(ModelCatalog.displayName(of: "llama3.1:8b"), "llama3.1:8b")
    }

    func testEachModelRunsOnTheEngineWithItsOwnFlagsAndAnyOtherNameRunsTheDefault() {
        for model in NoteModel.all {
            let backend = ModelCatalog.backend(for: model.id) as? EngineBackend
            XCTAssertEqual(backend?.label, model.displayName)
            XCTAssertEqual(backend?.install, model.install)
            XCTAssertEqual(backend?.serverArguments, model.serverArguments)
        }
        // A name left from a model the app no longer offers.
        XCTAssertEqual((ModelCatalog.backend(for: "llama3.1:8b") as? EngineBackend)?.label, "Gemma 4 E4B")
    }

    func testWithoutItsFileAModelPointsAtSettings() async {
        let nowhere = EngineBackend.Install(server: URL(fileURLWithPath: "/nowhere/llama-server"), weights: URL(fileURLWithPath: "/nowhere/gemma.gguf"))
        do { try await EngineBackend(.gemma, install: nowhere).check(); XCTFail("ready") } catch {
            XCTAssertEqual(error.localizedDescription, "Gemma 4 E4B's model file isn't on this Mac. Get it in Settings (Cmd-comma).")
        }
    }

    func testInstalledNamesTheModelsWhoseFileIsHereInOrder() {
        XCTAssertEqual(ModelCatalog.installed { _ in false }, [])
        XCTAssertEqual(ModelCatalog.installed { $0 != .qwen }, ["gemma4-e4b", "bonsai"])
    }

    func testAnEightGigabyteMacIsToldDraftingMayTakeLongerWithAnyModel() {
        for model in NoteModel.all.map(\.id) {
            let advice = ModelCatalog.memoryAdvice(for: model, memory: small)
            XCTAssertTrue(advice?.hasSuffix("this Mac has 8 GB of memory, so drafting may take longer.") == true, advice ?? "nil")
            XCTAssertNil(ModelCatalog.memoryAdvice(for: model, memory: roomy))
        }
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "bonsai", memory: nil))
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "qwen3:8b", memory: small))      // not offered, so no figure
    }

    func testTheMemoryCheckGivesTheFiguresAndNeverWarnsAboutSpeed() {
        XCTAssertEqual(ModelCatalog.memoryCheck(roomy, model: "bonsai"), Check("Memory", .ok, "16 GB, about 6 GB free now."))
        let noted = ModelCatalog.memoryCheck(small, model: "bonsai")
        XCTAssertEqual(noted.status, .ok)
        XCTAssertEqual(noted.detail, "8 GB, about 7 GB free now. Bonsai takes about 8 GB and this Mac has 8 GB of memory, so drafting may take longer.")
        XCTAssertEqual(ModelCatalog.memoryCheck(nil, model: "bonsai").status, .warning)
    }
}
