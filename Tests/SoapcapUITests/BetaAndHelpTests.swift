import XCTest
@testable import SoapcapUI

final class BetaAndHelpTests: XCTestCase {
    func testEveryVersionBelowOneIsABeta() {
        XCTAssertTrue(Beta.isBeta("0.11.0"))
        XCTAssertTrue(Beta.isBeta("0.1"))
        XCTAssertTrue(Beta.isBeta(""), "a copy with no version is a development copy")
        XCTAssertFalse(Beta.isBeta("1.0.0"))
        XCTAssertFalse(Beta.isBeta("2.3.1"))
    }

    func testTheNoticeIsAcknowledgedOnceForEachVersion() {
        XCTAssertTrue(Beta.needsNotice(version: "0.11.0", seen: ""))
        XCTAssertFalse(Beta.needsNotice(version: "0.11.0", seen: "0.11.0"))
        XCTAssertTrue(Beta.needsNotice(version: "0.12.0", seen: "0.11.0"), "an update asks again")
        XCTAssertFalse(Beta.needsNotice(version: "1.0.0", seen: "0.11.0"), "gone at 1.0")
        XCTAssertFalse(Beta.needsNotice(version: "", seen: ""), "nothing to acknowledge without a version")
    }

    func testTheAboutBoxSaysBetaBelowOne() {
        XCTAssertEqual(Beta.aboutVersion("0.11.0"), "0.11.0 Beta")
        XCTAssertEqual(Beta.aboutVersion("1.0.0"), "1.0.0")
        XCTAssertEqual(Beta.aboutVersion(""), "")
    }

    func testTheHelpPageIsReadIntoSections() {
        let page = """
        # Title, left out

        ## First
        A paragraph
        on two lines.

        - one
        - two

        ## Second
        Last.
        """
        XCTAssertEqual(HelpPage.sections(from: page), [
            HelpPage.Section(title: "First", blocks: [.paragraph("A paragraph on two lines."), .list(["one", "two"])]),
            HelpPage.Section(title: "Second", blocks: [.paragraph("Last.")]),
        ])
    }

    func testTheShippedHelpPageHasSectionsWithText() {
        XCTAssertGreaterThanOrEqual(HelpPage.sections.count, 5)
        for section in HelpPage.sections {
            XCTAssertFalse(section.blocks.isEmpty, "\(section.title) is empty")
        }
    }

    func testAProblemReportNamesTheVersionAndKeepsItsTextIntact() throws {
        let report = ProblemReport(version: AppVersion(marketing: "0.11.0", build: "149"),
                                   macOS: "Version 26.1 (Build 25B78)", memoryGB: 16, noteModel: "llama3.1:8b")
        let url = report.mailURL
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertFalse(url.absoluteString.contains(" "))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "subject" }?.value, "Soapcap 0.11.0 (149): a problem")
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("Soapcap 0.11.0 (149)\nmacOS Version 26.1 (Build 25B78)\nMemory 16 GB\nNote model llama3.1:8b"))
    }
}
