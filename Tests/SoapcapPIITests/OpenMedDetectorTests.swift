import XCTest
import SoapcapDeidentify
@testable import SoapcapPII

/// Runs the real model, so it is skipped on a Mac where the model isn't installed.
final class OpenMedDetectorTests: XCTestCase {
    func testTheModelRemovesANameAndAPhoneNumberButNotTheSpeakerLabel() async throws {
        try XCTSkipUnless(ModelFiles.isReady(), "the de-identification model isn't installed")
        let result = try await Deidentifier(detector: OpenMedDetector())
            .deidentify("Jordan: My name is Jordan Fitzgerald — call me on 555-0199.", kind: .transcript)
        XCTAssertEqual(result.text, "Jordan: My name is [FIRST_NAME_1] [LAST_NAME_1] — call me on [PHONE_1].")
    }

    func testAFolderWithoutTheModelIsAnErrorNotAnEmptyResult() async {
        let empty = FileManager.default.temporaryDirectory.appending(path: "no-model-\(UUID().uuidString)")
        do {
            _ = try await OpenMedDetector(directory: empty).spans(in: "My name is Jordan.")
            XCTFail("expected a throw")
        } catch {}
    }
}
