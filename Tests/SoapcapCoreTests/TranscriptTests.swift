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

    func testSortsByStartAndDropsBlankSegments() {
        XCTAssertEqual(Transcript.render([seg("Client", 3, 4, 2, " fine "), seg("Therapist", 1, 2, 1, "Hello"),
                                          seg("Client", 2, 2, 3, "  ")]),
                       "Therapist: Hello\nClient: fine")
    }

    func testDecodesYapJSONWithMissingFields() throws {
        let json = #"{"segments":[{"end":2.0,"id":1,"start":0.5,"text":"A recorded line"},{"text":"bare"}]}"#
        let segments = try Segment.decode(yapJSON: Data(json.utf8))
        XCTAssertEqual(segments, [Segment(speaker: "Speaker", start: 0.5, end: 2, id: 1, text: "A recorded line"),
                                  Segment(text: "bare")])
        XCTAssertEqual(try Segment.decode(yapJSON: Data("{}".utf8)), [])
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
