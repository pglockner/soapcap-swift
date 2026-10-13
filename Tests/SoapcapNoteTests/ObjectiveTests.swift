import XCTest
@testable import SoapcapNote

/// The same cases as soapcap's test/run.sh "SOAP Objective" section.
final class ObjectiveTests: XCTestCase {
    private let status = ["engagement": "engaged and collaborative", "affect": "congruent", "mood": "mildly stressed.",
                          "speech": "clear", "thought_process": "linear", "insight": "improving",
                          "judgment": "intact", "psychomotor": "no psychomotor abnormalities"]
    private let frame = "On time via video. Engaged and collaborative. Affect congruent; mood mildly stressed. Speech clear. Thought process linear. Insight improving; judgment intact. No psychomotor abnormalities."

    private func render(risk: String = "not_addressed", kind: String = "", note: String = "x",
                        _ change: (inout [String: String]) -> Void = { _ in }) -> String {
        var status = status
        change(&status)
        return Objective.render(.assessed(.init(mentalStatus: status, riskStatus: risk, riskKind: kind)), note: note)
    }

    func testFillsTheFixedFrameTrimmingTrailingPeriods() {
        XCTAssertEqual(render(note: "PLAN: Continue."), frame + " No SI/HI reported.")
    }

    func testADisclosureIsNamedByKindInFixedWords() {
        XCTAssertEqual(render(risk: "disclosed", kind: "SI"), frame + " SI reported; see Assessment and Plan.")
        XCTAssertEqual(render(risk: "disclosed", kind: "SI and HI"), frame + " SI and HI reported; see Assessment and Plan.")
        XCTAssertEqual(render(risk: "disclosed", kind: "self-harm"), frame + " Self-harm reported; see Assessment and Plan.")
        XCTAssertEqual(render(risk: "disclosed", kind: "none"), frame + " Safety risk reported; see Assessment and Plan.")
    }

    func testRiskInTheNoteMissedByThePassBlocksNoSIHI() {
        let flag = "[The note mentions a safety concern; confirm SI/HI status before signing.]"
        XCTAssertTrue(render(note: "The client said everyone would be better off without them.").hasSuffix(flag))
        XCTAssertTrue(render(note: "Reported urges to self-harm.").hasSuffix(flag))
        XCTAssertTrue(render(note: "The client denied a plan but reported passive suicidal ideation.").hasSuffix(flag))
        XCTAssertTrue(render(note: "A safety plan was reviewed.").hasSuffix(flag))
        XCTAssertTrue(render(note: "Client has thoughts of wanting to harm others.").hasSuffix(flag))
        XCTAssertTrue(render(note: "Denies suicidal ideation; however, reports homicidal thoughts.").hasSuffix(flag))
    }

    func testAPlainDenialInTheNoteIsStillNoSIHI() {
        XCTAssertEqual(render(note: "The client denied suicidal ideation."), frame + " No SI/HI reported.")
        XCTAssertEqual(render(note: "There is no indication of self-harm or suicidal ideation."), frame + " No SI/HI reported.")
        XCTAssertEqual(render(note: "Client denies suicidal thoughts and homicidal ideation."), frame + " No SI/HI reported.")
    }

    func testAFailedPassAndNoClientSpeechMakeNoSIHIClaim() {
        XCTAssertEqual(Objective.render(.failed, note: "x"),
                       "On time via video. [Objective could not be drafted; complete manually.] [SI/HI status not assessed; confirm before signing.]")
        XCTAssertEqual(Objective.render(.noClient, note: "x"),
                       "On time via video. [No client speech was captured; complete the Objective manually.] [SI/HI status not assessed; confirm before signing.]")
    }

    func testABlankFieldShowsRatherThanVanishing() {
        XCTAssertTrue(render { $0["affect"] = "" }.contains("Affect [not assessed]; mood"))
        XCTAssertTrue(render { $0["affect"] = nil }.contains("Affect [not assessed]; mood"))
    }

    func testSlotsKeepAcronymsAndLowercaseOrdinaryWords() {
        XCTAssertTrue(render { $0["affect"] = "Constricted" }.contains("Affect constricted;"))
        XCTAssertTrue(render { $0["speech"] = "WNL" }.contains("Speech WNL."))
    }

    func testReadsTheModelsJSON() {
        let json = #"{"mental_status": {"engagement": "open", "affect": "full range"}, "risk": {"status": "disclosed", "summary": ""}, "risk_kind": "HI"}"#
        XCTAssertEqual(Objective.result(fromJSON: json),
                       .assessed(.init(mentalStatus: ["engagement": "open", "affect": "full range"], riskStatus: "disclosed", riskKind: "HI")))
        XCTAssertEqual(Objective.result(fromJSON: #"{"mental_status": "calm"}"#), .failed)
        XCTAssertEqual(Objective.result(fromJSON: "null"), .failed)
        XCTAssertEqual(Objective.result(fromJSON: #"{"mental_status": {"mood": "low"#), .failed)
    }

    func testAnySectionOfANoteCanBeSetWhereverItIsOrIsNot() {
        let body = "[placeholder]"
        // In place, whatever markup the header has and however long the old body.
        XCTAssertEqual(NoteText.setting("SUBJECTIVE", to: body, in: "**SUBJECTIVE:** The client said\nmore.\n\nASSESSMENT:\nA.\n\nPLAN:\nP."),
                       "SUBJECTIVE:\n[placeholder]\n\nASSESSMENT:\nA.\n\nPLAN:\nP.")
        // Missing: it goes before the first section that follows it.
        XCTAssertEqual(NoteText.setting("SUBJECTIVE", to: body, in: "ASSESSMENT:\nA.\n\nPLAN:\nP."),
                       "SUBJECTIVE:\n[placeholder]\n\nASSESSMENT:\nA.\n\nPLAN:\nP.")
        // The last section, missing: at the end.
        XCTAssertEqual(NoteText.setting("PLAN", to: body, in: "SUBJECTIVE:\nS."), "SUBJECTIVE:\nS.\n\nPLAN:\n[placeholder]")
    }

    // MARK: splice

    private let spliced = "SUBJECTIVE:\nS.\n\nOBJECTIVE:\nBODY\n\nASSESSMENT:\nA.\n\nPLAN:\nP."

    func testSpliceReplacesTheObjectivesBody() {
        XCTAssertEqual(Objective.splice("BODY", into: "SUBJECTIVE:\nS.\n\nOBJECTIVE:\nold\nlines\n\nASSESSMENT:\nA.\n\nPLAN:\nP.\n"), spliced)
    }

    func testSpliceHandlesMarkupTextOnTheHeaderLineAndASecondObjective() {
        XCTAssertEqual(Objective.splice("BODY", into: "SUBJECTIVE:\nS.\n\n**OBJECTIVE:** old\n\nASSESSMENT:\nA.\n\nOBJECTIVE:\nagain\n\nPLAN:\nP.\n"), spliced)
    }

    func testSpliceInsertsAMissingObjectiveBeforeAssessment() {
        XCTAssertEqual(Objective.splice("BODY", into: "SUBJECTIVE:\nS.\n\nASSESSMENT:\nA.\n\nPLAN:\nP.\n"), spliced)
    }

    func testSpliceAppendsWhenThereIsNowhereToPutIt() {
        XCTAssertEqual(Objective.splice("BODY", into: "SUBJECTIVE:\nS.\n"), "SUBJECTIVE:\nS.\n\nOBJECTIVE:\nBODY")
    }
}

final class PromptsTests: XCTestCase {
    func testEachFormatsPromptEndsWithTheTranscript() throws {
        for format in NoteFormat.allCases {
            let prompt = try Prompts.draft(format, transcript: "Client: hello")
            XCTAssertTrue(prompt.hasSuffix("\n\nTRANSCRIPT:\nClient: hello"), format.rawValue)
            XCTAssertGreaterThan(prompt.count, 1000)
        }
        XCTAssertTrue(try Prompts.objective(transcript: "Client: hello").hasSuffix("\nTRANSCRIPT:\nClient: hello\n"))
    }

    func testTheObjectiveSchemaHasItsThreeFields() throws {
        let schema = try JSONSerialization.jsonObject(with: try Prompts.objectiveSchema()) as? [String: Any] ?? [:]
        XCTAssertEqual(schema["required"] as? [String], ["mental_status", "risk", "risk_kind"])
        XCTAssertEqual((schema["properties"] as? [String: Any])?.keys.sorted(), ["mental_status", "risk", "risk_kind"])
    }

    /// The prompts are soapcap's; this notices when the two copies drift apart.
    func testPromptsMatchSoapcapsWhenItsCheckoutIsHere() throws {
        let theirs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("projects/soapcap/prompts")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: theirs.path), "no soapcap checkout")
        for file in ["soap.md", "dap.md", "birp.md", "objective.md", "structured/schema.json"] {
            XCTAssertEqual(try Prompts.read(file), try String(contentsOf: theirs.appendingPathComponent(file), encoding: .utf8), file)
        }
    }
}
