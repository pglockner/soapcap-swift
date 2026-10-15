import XCTest
@testable import SoapcapCore

final class MemoryStatusTests: XCTestCase {
    private let gb: UInt64 = 1 << 30

    func testAdviceComesOnlyWhenTheModelWontFitWithRoomToSpare() {
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 68).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 41).advice(beforeLoading: "Bonsai", needGB: 8),
                       "About 6 GB of memory is free and Bonsai takes about 8 GB. Close other apps before drafting, or it will be slow.")
        XCTAssertNil(MemoryStatus(totalBytes: 64 * gb, freePercent: 20).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 8 * gb, freePercent: 90).advice(beforeLoading: "Bonsai", needGB: 8),
                       "Bonsai takes about 8 GB and this Mac has 8 GB of memory. Expect drafting to be very slow.")
    }

    func testAQuestionComesOnlyWhenTheModelWontFitAndSwapIsAlreadyHeavy() {
        let heavy = 6 * gb, light = 4 * gb
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 41, swapUsedBytes: heavy, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 30, swapUsedBytes: light, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 30, swapUsedBytes: heavy, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8),
                       "About 4 GB of memory is free and 6 GB is already in swap. Bonsai takes about 8 GB. Drafting now will be very slow and may slow the whole Mac. Close other apps first, or choose a lighter model in Settings.")
    }

    func testTheCurrentFiguresCanBeRead() throws {
        let now = try XCTUnwrap(MemoryStatus.current())
        XCTAssertGreaterThan(now.totalBytes, gb)
        XCTAssertTrue((0...100).contains(now.freePercent))
    }
}
