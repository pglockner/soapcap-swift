import XCTest
@testable import SoapcapCore

final class MemoryStatusTests: XCTestCase {
    private let gb: UInt64 = 1 << 30

    func testOnlyAMacWithTooLittleMemoryInAllIsToldDraftingMayTakeLonger() {
        // What is free or in swap doesn't count: drafts ran at their usual pace either way.
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 5, swapUsedBytes: 12 * gb, swapTotalBytes: 13 * gb).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertNil(MemoryStatus(totalBytes: 12 * gb, freePercent: 90).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 8 * gb, freePercent: 90).advice(beforeLoading: "Bonsai", needGB: 8),
                       "Bonsai takes about 8 GB and this Mac has 8 GB of memory, so drafting may take longer.")
    }

    func testTheCurrentFiguresCanBeRead() throws {
        let now = try XCTUnwrap(MemoryStatus.current())
        XCTAssertGreaterThan(now.totalBytes, gb)
        XCTAssertTrue((0...100).contains(now.freePercent))
    }
}
