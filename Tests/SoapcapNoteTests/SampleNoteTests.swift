import XCTest
@testable import SoapcapNote

/// Drafts the note of the sample session in Samples/notes with a real
/// model, run the way the app would run it: the baseline check that a model
/// on this Mac is working. Only when SOAPCAP_MODEL_TESTS is set, since it
/// loads a model and takes about a minute. `1` means the default model; any
/// other value names the model to try.
final class SampleNoteTests: XCTestCase {
    func testTheSampleSessionBecomesAWholeNote() async throws {
        let asked = ProcessInfo.processInfo.environment["SOAPCAP_MODEL_TESTS"] ?? ""
        try XCTSkipUnless(!asked.isEmpty, "set SOAPCAP_MODEL_TESTS to run")
        let model = asked == "1" ? ModelCatalog.defaultModel : asked

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let transcript = try String(contentsOf: root.appendingPathComponent("Samples/notes/03-selfreport-diagnosis-9min.txt"), encoding: .utf8)
            .trimmingCharacters(in: .newlines)
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
            note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: transcript, minutes: 9)
        } catch {
            await backend.stop()
            throw error
        }
        await backend.stop()

        XCTAssertTrue(note.text.hasPrefix("9 minutes, telehealth\n"), note.text)
        XCTAssertEqual(NoteFaults.faults(in: note.text, sections: ["SUBJECTIVE", "OBJECTIVE", "ASSESSMENT", "PLAN"]), [], note.text)
        // Nothing left incomplete, no failed Objective pass, no cut-off reply.
        XCTAssertEqual(note.warnings, [], note.text)
    }
}
