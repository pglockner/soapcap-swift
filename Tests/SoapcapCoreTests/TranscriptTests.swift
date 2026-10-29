import XCTest
@testable import SoapcapCore

/// The same cases as soapcap's test/run.sh, so the two implementations agree.
final class TranscriptTests: XCTestCase {
    private func seg(_ speaker: String, _ start: Double, _ end: Double, _ id: Int, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: end, id: id, text: text)
    }

    private func render(_ segments: [Segment], dedupe: Bool = true) -> String {
        Transcript.render(segments, mic: "Therapist", system: "Client", dedupe: dedupe ? .init() : nil)
    }

    private let echo = [
        Segment(speaker: "Client", start: 0, end: 2, id: 1, text: "How was your week going overall"),
        Segment(speaker: "Therapist", start: 2.5, end: 3, id: 2, text: "going overall"),
    ]

    func testDropsMicSideEchoOfSystemSideUtterance() {
        XCTAssertEqual(render(echo), "Client: How was your week going overall")
    }

    func testKeepsOverlappingTimeButDifferentContent() {
        XCTAssertEqual(render([seg("Client", 0, 2, 1, "How was your week"),
                               seg("Therapist", 1, 2, 2, "I have been stressed")]),
                       "Client: How was your week\nTherapist: I have been stressed")
    }

    func testKeepsSameContentFarApartInTime() {
        XCTAssertEqual(render([seg("Client", 0, 2, 1, "going overall"),
                               seg("Therapist", 60, 61, 2, "going overall")]),
                       "Client: going overall\nTherapist: going overall")
    }

    func testKeepsLongerMicSegmentAShortReplyRepeats() {
        XCTAssertEqual(render([seg("Therapist", 0, 2, 1, "So you barely slept this week"),
                               seg("Client", 2.5, 3, 2, "barely slept")]),
                       "Therapist: So you barely slept this week\nClient: barely slept")
    }

    func testNeverDropsBackchannelBelowMinWords() {
        XCTAssertEqual(render([seg("Client", 0, 1, 1, "Okay"), seg("Therapist", 0.5, 1, 2, "Okay")]),
                       "Client: Okay\nTherapist: Okay")
    }

    func testNoDedupeKeepsEverything() {
        XCTAssertEqual(render(echo, dedupe: false),
                       "Client: How was your week going overall\nTherapist: going overall")
    }

    func testMergesConsecutiveSameSpeakerSegments() {
        XCTAssertEqual(Transcript.render([seg("Client", 0, 1, 1, "First part."),
                                          seg("Client", 1, 2, 2, "Second part.")], dedupe: nil),
                       "Client: First part. Second part.")
    }

    func testATurnBeginsWhenItsFirstSegmentDid() {
        let turns = Transcript.turns([seg("Client", 61.5, 63, 1, "First part."), seg("Client", 64, 66, 2, "Second part."),
                                      seg("Therapist", 70, 71, 1, "Go on.")], dedupe: nil)
        XCTAssertEqual(turns.map(\.start), [61.5, 70])
        XCTAssertEqual(Transcript.render(turns), "Client: First part. Second part.\nTherapist: Go on.")
    }

    func testSortsByStartAndDropsBlankSegments() {
        XCTAssertEqual(Transcript.render([seg("Client", 3, 4, 2, " fine "), seg("Therapist", 1, 2, 1, "Hello"),
                                          seg("Client", 2, 2, 3, "  ")]),
                       "Therapist: Hello\nClient: fine")
    }

    func testASegmentWithNoWordInItIsDropped() {
        // A breath or a click, heard as a lone full stop.
        XCTAssertEqual(Transcript.render([seg("Client", 1, 2, 1, "Start."), seg("Therapist", 2, 3, 2, "."),
                                          seg("Client", 3, 4, 3, "Just so you know."), seg("Therapist", 4, 5, 4, "OK, 5.")]),
                       "Client: Start. Just so you know.\nTherapist: OK, 5.")
    }

    func testDecodesYapJSONWithMissingFields() throws {
        let json = #"{"segments":[{"end":2.0,"id":1,"start":0.5,"text":"A recorded line"},{"text":"bare"}]}"#
        let segments = try YapJSON.segments(Data(json.utf8))
        XCTAssertEqual(segments, [Segment(speaker: "Speaker", start: 0.5, end: 2, id: 1, text: "A recorded line"),
                                  Segment(text: "bare")])
        XCTAssertEqual(try YapJSON.segments(Data("{}".utf8)), [])
    }

    func testWordsAreLowercasedASCIIAndDistinct() {
        XCTAssertEqual(Transcript.words("Yeah, yeah — it's 9am!"), ["yeah", "it", "s", "9am"])
    }

    func testOneSidedNoticeOnlyWhenTheOtherPartyIsMissing() {
        let mic = Segment(speaker: "Therapist", text: "hello")
        let sys = Segment(speaker: "Client", text: "hi")
        XCTAssertNotNil(Transcript.oneSidedNotice([mic], mic: "Therapist", system: "Client"))
        XCTAssertNil(Transcript.oneSidedNotice([mic, sys], mic: "Therapist", system: "Client"))
        XCTAssertNil(Transcript.oneSidedNotice([sys], mic: "Therapist", system: "Client"))
        XCTAssertNil(Transcript.oneSidedNotice([], mic: "Therapist", system: "Client"))
    }
}
