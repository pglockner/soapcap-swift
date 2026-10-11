import XCTest
@testable import SoapcapUI

final class AcknowledgementsTests: XCTestCase {
    func testEveryPackageTheBuildPullsInIsCreditedWithItsLicence() throws {
        let resolved = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.resolved")
        struct Resolved: Decodable { struct Pin: Decodable { let identity: String }; let pins: [Pin] }
        let pins = try JSONDecoder().decode(Resolved.self, from: Data(contentsOf: resolved)).pins.map(\.identity)
        XCTAssertFalse(pins.isEmpty)
        let credited = Set(Credit.all.compactMap(\.package))
        XCTAssertEqual(pins.filter { !credited.contains($0) }, [], "packages with no entry in credits.json")
        for credit in Credit.all {
            XCTAssertFalse((credit.licenseText ?? "").isEmpty, "no licence text for \(credit.name)")
        }
    }
}
