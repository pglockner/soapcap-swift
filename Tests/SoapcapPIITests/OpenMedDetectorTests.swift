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

/// The samples in Samples/deidentify, which the passes were not chosen on.
/// Runs the real model, so it is skipped where the model isn't installed.
final class HeldOutSampleTests: XCTestCase {
    func testEverythingListedForRemovalIsGone() async throws {
        try XCTSkipUnless(ModelFiles.isReady(), "the de-identification model isn't installed")
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/deidentify")
        let samples = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertFalse(samples.isEmpty)
        let deidentifier = Deidentifier(detector: OpenMedDetector())
        for sample in samples {
            let text = try String(contentsOf: sample, encoding: .utf8).trimmingCharacters(in: .newlines)
            let result = try await deidentifier.deidentify(text, kind: .transcript).text
            XCTAssertEqual(result.split(separator: "\n").count, text.split(separator: "\n").count)
            let listed = try String(contentsOf: sample.deletingPathExtension().appendingPathExtension("remove"), encoding: .utf8)
            for line in listed.split(separator: "\n") where !line.hasPrefix("? ") {
                let wholeWord = try NSRegularExpression(pattern: #"(?<!\w)"# + NSRegularExpression.escapedPattern(for: String(line)) + #"(?!\w)"#)
                XCTAssertNil(wholeWord.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                             "\(sample.lastPathComponent) still contains \(line)")
            }
        }
    }
}
