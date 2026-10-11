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

final class MemoryStatusTests: XCTestCase {
    private let gb: UInt64 = 1 << 30

    func testUsedCountsSwapSoItPassesAHundredWhenSwapping() {
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 67).usedPercent, 33)
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 5, swapUsedBytes: 4 * gb, swapTotalBytes: 5 * gb).usedPercent, 120)
    }

    func testLevelsTurnAtSeventyFiveAndNinety() {
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 26).level, .ok)
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 25).level, .high)
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 10).level, .critical)
    }

    func testTheSummaryAddsSwapOnlyWhenCritical() {
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 20, swapUsedBytes: gb, swapTotalBytes: 2 * gb).summary, "memory 86%")
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 6, swapUsedBytes: 2254 << 20, swapTotalBytes: 5 * gb).summary,
                       "memory 107%   swap 44% (2.2 GB)")
    }

    func testAdviceComesOnlyWhenTheModelWontFitWithRoomToSpare() {
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 68).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 41).advice(beforeLoading: "Bonsai", needGB: 8),
                       "About 6 GB of memory is free and Bonsai takes about 8 GB. Close other apps before drafting, or it will be slow.")
        XCTAssertNil(MemoryStatus(totalBytes: 64 * gb, freePercent: 20).advice(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 8 * gb, freePercent: 90).advice(beforeLoading: "Bonsai", needGB: 8),
                       "Bonsai takes about 8 GB and this Mac has 8 GB of memory. Expect drafting to be very slow.")
    }

    func testAQuestionComesOnlyWhenTheModelWontFitAndSwapIsAlreadyHeavy() {
        let heavy = 6 * gb, light = 4 * gb
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 41, swapUsedBytes: heavy, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertNil(MemoryStatus(totalBytes: 16 * gb, freePercent: 30, swapUsedBytes: light, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8))
        XCTAssertEqual(MemoryStatus(totalBytes: 16 * gb, freePercent: 30, swapUsedBytes: heavy, swapTotalBytes: 8 * gb).question(beforeLoading: "Bonsai", needGB: 8),
                       "About 4 GB of memory is free and 6 GB is already in swap. Bonsai takes about 8 GB. Drafting now will be very slow and may slow the whole Mac. Close other apps first, or choose a lighter model in Settings.")
    }

    func testTheCurrentFiguresCanBeRead() throws {
        let now = try XCTUnwrap(MemoryStatus.current())
        XCTAssertGreaterThan(now.totalBytes, gb)
        XCTAssertTrue((0...100).contains(now.freePercent))
    }
}
