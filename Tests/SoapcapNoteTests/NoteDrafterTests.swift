import XCTest
@testable import SoapcapNote

/// A model stand-in that answers from a script, one reply per request.
final class ScriptedBackend: NoteBackend, @unchecked Sendable {
    let label = "test-model"
    var cautions: [String] = []
    var drafts: [Result<ModelReply, NoteError>]
    var objectives: [Result<ModelReply, NoteError>]
    var log: [String] = []
    var contexts: [Int] = []
    var prompts: [String] = []

    init(drafts: [String], objectives: [String] = [goodObjective]) {
        self.drafts = drafts.map { .success(ModelReply(text: $0)) }
        self.objectives = objectives.map { .success(ModelReply(text: $0)) }
    }

    func check() async throws {}
    func start(context: Int) async throws { log.append("start"); contexts.append(context) }
    func stop() async { log.append("stop") }

    func request(prompt: String, cap: Int, schema: Data?, tokens: @escaping @Sendable (Int) -> Void) async throws -> ModelReply {
        prompts.append(prompt)
        tokens(1)
        if schema == nil {
            log.append("draft")
            // Like soapcap's test stand-in: past the end of the script, a good draft.
            return try (drafts.isEmpty ? .success(ModelReply(text: good)) : drafts.removeFirst()).get()
        }
        log.append("objective cap \(cap)")
        return try (objectives.count > 1 ? objectives.removeFirst() : objectives[0]).get()
    }
}

let good = "SUBJECTIVE:\nSlept badly.\n\nASSESSMENT:\nStress.\n\nPLAN:\nWeekly."
let bad = "SUBJECTIVE:\nSlept badly.\n\nASSESSMENT:\nNot addressed in this session.\n\nPLAN:\nWeekly."
let worse = "SUBJECTIVE:\nSlept badly."
let goodObjective = #"{"mental_status": {"engagement": "engaged", "affect": "congruent", "mood": "stressed", "speech": "clear", "thought_process": "linear", "insight": "good", "judgment": "intact", "psychomotor": "no psychomotor abnormalities"}, "risk": {"status": "not_addressed", "summary": ""}, "risk_kind": "none"}"#
private let frame = "On time via video. Engaged. Affect congruent; mood stressed. Speech clear. Thought process linear. Insight good; judgment intact. No psychomotor abnormalities. No SI/HI reported."

final class NoteDrafterTests: XCTestCase {
    private func long(_ speaker: String = "Client") -> String {
        String(repeating: "\(speaker): word ", count: 100).replacingOccurrences(of: " \(speaker)", with: "\n\(speaker)")
    }

    private func withObjective(_ note: String, _ body: String = frame) -> String {
        note.replacingOccurrences(of: "\n\nASSESSMENT:", with: "\n\nOBJECTIVE:\n\(body)\n\nASSESSMENT:")
    }

    func testDraftsAgainAfterAnIncompleteDraftAndStopsAtACompleteOne() async throws {
        let backend = ScriptedBackend(drafts: [bad, good])
        let note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long())
        XCTAssertEqual(backend.log, ["start", "draft", "draft", "objective cap 600"])
        XCTAssertEqual(note.text, withObjective(good))
        XCTAssertEqual(note.warnings, [])
    }

    func testGivesUpAfterThreeDraftsKeepingTheMostComplete() async throws {
        let backend = ScriptedBackend(drafts: [bad, worse, bad])
        let note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long())
        XCTAssertEqual(backend.log.filter { $0 == "draft" }.count, 3)
        XCTAssertEqual(note.text, withObjective(bad))
        XCTAssertEqual(note.warnings, ["The note is still incomplete after 3 drafts (ASSESSMENT is empty or \"Not addressed\") — check it against the transcript."])
    }

    func testATranscriptWithNoClientSpeechGetsOneDraftAndNoObjectivePass() async throws {
        let backend = ScriptedBackend(drafts: [bad, good])
        let note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long("Therapist"))
        XCTAssertEqual(backend.log, ["start", "draft"])
        XCTAssertEqual(note.text, withObjective(bad, "On time via video. [No client speech was captured; complete the Objective manually.] [SI/HI status not assessed; confirm before signing.]"))
        XCTAssertEqual(note.warnings, ["No Client lines in the transcript — the Objective is left for you to complete."])
    }

    func testAShortTranscriptIsLenientAboutHollowSections() async throws {
        let backend = ScriptedBackend(drafts: [bad, good])
        _ = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: "Client: hello there")
        XCTAssertEqual(backend.log.filter { $0 == "draft" }.count, 1)
    }

    func testTheCallLabelDecidesWhoTheClientIs() async throws {
        let backend = ScriptedBackend(drafts: [good])
        var drafter = NoteDrafter(backend: backend)
        drafter.systemLabel = "Patient"
        let note = try await drafter.draft(format: .soap, transcript: "Patient: hello there")
        XCTAssertEqual(note.warnings, [])
        XCTAssertTrue(backend.log.contains("objective cap 600"))
    }

    func testAMalformedObjectiveIsRetriedOnceThenLeftForTheClinician() async throws {
        let recovered = ScriptedBackend(drafts: [good], objectives: [#"{"mental_status": {}}"#, goodObjective])
        let first = try await NoteDrafter(backend: recovered).draft(format: .soap, transcript: long())
        XCTAssertEqual(first.text, withObjective(good))
        XCTAssertEqual(recovered.log.filter { $0.hasPrefix("objective") }.count, 2)

        let failed = ScriptedBackend(drafts: [good], objectives: ["not json"])
        let second = try await NoteDrafter(backend: failed).draft(format: .soap, transcript: long())
        XCTAssertTrue(second.text.contains("[Objective could not be drafted; complete manually.] [SI/HI status not assessed"))
        XCTAssertEqual(second.warnings, ["The Objective pass failed — complete the Objective by hand."])
        XCTAssertEqual(failed.log.filter { $0.hasPrefix("objective") }.count, 2)
    }

    func testACutOffObjectiveDoesNotCount() async throws {
        let backend = ScriptedBackend(drafts: [good])
        backend.objectives = [.success(ModelReply(text: goodObjective, cutOff: true))]
        let note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long())
        XCTAssertEqual(note.warnings, ["The Objective pass failed — complete the Objective by hand."])
    }

    func testAFailedObjectiveRequestKeepsTheNote() async throws {
        let backend = ScriptedBackend(drafts: [good])
        backend.objectives = [.failure(.requestFailed("boom"))]
        let note = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long())
        XCTAssertTrue(note.text.hasPrefix("SUBJECTIVE:\nSlept badly."))
        XCTAssertEqual(backend.log.filter { $0.hasPrefix("objective") }.count, 1)
    }

    func testAFailedFirstDraftIsAnErrorButALaterFailureKeepsTheBestSoFar() async throws {
        let dead = ScriptedBackend(drafts: [])
        dead.drafts = [.failure(.requestFailed("boom"))]
        do { _ = try await NoteDrafter(backend: dead).draft(format: .dap, transcript: long()); XCTFail("drafted") } catch {
            XCTAssertEqual(error as? NoteError, .requestFailed("boom"))
        }
        let flaky = ScriptedBackend(drafts: [])
        flaky.drafts = [.success(ModelReply(text: bad)), .failure(.requestFailed("boom"))]
        let note = try await NoteDrafter(backend: flaky).draft(format: .soap, transcript: long())
        XCTAssertTrue(note.text.contains("Not addressed in this session."))
    }

    func testACutOffDraftAndTheBackendsCautionsAreReported() async throws {
        let backend = ScriptedBackend(drafts: [])
        backend.drafts = [.success(ModelReply(text: "DATA:\nx\n\nASSESSMENT:\ny\n\nPLAN:\nz", cutOff: true))]
        backend.cautions = ["untested model"]
        let note = try await NoteDrafter(backend: backend).draft(format: .dap, transcript: long())
        XCTAssertEqual(note.warnings, ["untested model", "test-model hit its output limit — the end of the note may be cut off."])
        XCTAssertEqual(backend.log, ["start", "draft"], "only SOAP has an Objective pass")
        XCTAssertFalse(note.text.contains("OBJECTIVE"))
    }

    func testTheDraftIsCleanedAndGetsItsSessionLine() async throws {
        let backend = ScriptedBackend(drafts: ["DATA:\nx\n\nASSESSMENT:\ny\n\nPLAN:\nz\n\nNote: this looks like a test.\n\nTRANSCRIPT:\nClient: hi"])
        var drafter = NoteDrafter(backend: backend)
        drafter.sessionType = "in person"
        let note = try await drafter.draft(format: .dap, transcript: long(), minutes: 53)
        XCTAssertEqual(note.text, "53 minutes, in person\n\nDATA:\nx\n\nASSESSMENT:\ny\n\nPLAN:\nz")
    }

    func testOneContextSizeCoversBothPassesAndProgressIsReported() async throws {
        let backend = ScriptedBackend(drafts: [good])
        let seen = Seen()
        _ = try await NoteDrafter(backend: backend).draft(format: .soap, transcript: long()) { seen.add($0) }
        XCTAssertEqual(backend.contexts.count, 1)
        XCTAssertEqual(backend.contexts[0] % 1024, 0)
        XCTAssertGreaterThanOrEqual(backend.contexts[0], ContextSize.estimate(backend.prompts[1], headroom: 3072))
        XCTAssertEqual(seen.all.map(\.title).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } },
                       ["Loading test-model…", "Drafting a soap note with test-model…", "Drafting the Objective with test-model…"])
        XCTAssertTrue(seen.all.contains { $0.tokens == 1 })
    }
}

final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DraftProgress] = []
    func add(_ item: DraftProgress) { lock.withLock { items.append(item) } }
    var all: [DraftProgress] { lock.withLock { items } }
}
