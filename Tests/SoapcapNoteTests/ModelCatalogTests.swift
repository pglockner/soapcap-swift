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

    func testMemoryAdviceIsOnlyForAModelTheAppLoadsItself() {
        XCTAssertTrue(ModelCatalog.memoryAdvice(for: "bonsai", memory: short)?.hasPrefix("About 6 GB of memory is free and Bonsai takes") == true)
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "bonsai", memory: roomy))
        XCTAssertNil(ModelCatalog.memoryAdvice(for: "llama3.1:8b", memory: short))   // Ollama loads it, and may already hold it
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
