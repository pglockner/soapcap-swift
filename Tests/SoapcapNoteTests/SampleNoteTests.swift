import XCTest
@testable import SoapcapNote

/// The sample session itself, and what counts as a problem with its note.
final class SampleSessionTests: XCTestCase {
    private let whole = "9 minutes, telehealth\n\nSUBJECTIVE:\nSlept badly.\n\nOBJECTIVE:\nOn time via video.\n\nASSESSMENT:\nAnxious.\n\nPLAN:\nMeet again."

    func testTheSampleIsASessionWithBothSidesAndEnoughToFillANote() throws {
        let lines = try SampleSession.transcript().split(separator: "\n")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("Therapist: ") || $0.hasPrefix("\(SampleSession.systemLabel): ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("\(SampleSession.systemLabel): ") })
        // Under 150 words the drafter stops insisting on every section.
        XCTAssertGreaterThan(lines.joined(separator: " ").split(separator: " ").count, 500)
    }

    func testAWholeNoteWithNothingToCautionAboutHasNoProblems() {
        XCTAssertEqual(SampleSession.problems(in: DraftedNote(text: whole)), [])
        let untested = "qwen3:8b hasn't been tested"
        XCTAssertEqual(SampleSession.problems(in: DraftedNote(text: whole, warnings: [untested]), cautions: [untested]), [])
    }

    func testAnEmptySectionOrACautionFromTheDrafterIsAProblem() {
        let hollow = whole.replacingOccurrences(of: "Anxious.", with: "Not addressed in this session.")
        XCTAssertEqual(SampleSession.problems(in: DraftedNote(text: hollow)), ["ASSESSMENT is empty or \"Not addressed\""])
        let missing = whole.replacingOccurrences(of: "\n\nPLAN:\nMeet again.", with: "")
        XCTAssertEqual(SampleSession.problems(in: DraftedNote(text: missing)), ["no PLAN section"])
        let failed = "The Objective pass failed — complete the Objective by hand."
        XCTAssertEqual(SampleSession.problems(in: DraftedNote(text: whole, warnings: [failed])), [failed])
    }
}

/// Drafts the sample session's note with a real model, run the way the app
/// would run it: the baseline check that a model on this Mac is working,
/// and the same judgement the app's Test button makes. Only when
/// SOAPCAP_MODEL_TESTS is set, since it loads a model and takes about a
/// minute. `1` means the default model; any other value names the model.
final class SampleNoteTests: XCTestCase {
    func testTheSampleSessionBecomesAWholeNote() async throws {
        let asked = ProcessInfo.processInfo.environment["SOAPCAP_MODEL_TESTS"] ?? ""
        try XCTSkipUnless(!asked.isEmpty, "set SOAPCAP_MODEL_TESTS to run")
        let model = asked == "1" ? ModelCatalog.defaultModel : asked

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // The engine engine.sh builds, on a port of its own so that a
        // Soapcap that is open is left alone.
        let engine = root.appendingPathComponent(".build/engine/llama-server")
        let backend = ModelCatalog.backend(
            for: model, pulled: await ModelCatalog.pulled(),
            bonsai: .init(server: engine, weights: BonsaiBackend.Install.standard.weights, port: 18090),
            llama: .init(server: engine, weights: BonsaiBackend.Install.ownLlamaWeights, port: 18090))
        do { try await backend.check() } catch {
            throw XCTSkip("\(model) can't draft on this Mac: \(error.localizedDescription)")
        }

        let note: DraftedNote
        do {
            note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: try SampleSession.transcript(),
                                                                 minutes: SampleSession.minutes)
        } catch {
            await backend.stop()
            throw error
        }
        await backend.stop()

        XCTAssertTrue(note.text.hasPrefix("9 minutes, telehealth\n"), note.text)
        XCTAssertEqual(SampleSession.problems(in: note, cautions: backend.cautions), [], note.text)
    }
}
