import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import SoapcapUI

/// What Save transcript writes. Nothing here opens a save panel or writes a
/// file: the text and the bytes are looked at in memory.
final class TranscriptFileTests: XCTestCase {
    func testTheFileIsLaidOutByMinutesWithItsPauses() {
        let file = TranscriptFile(transcript: "Therapist: hi\nClient: hello\nTherapist: go on\nClient: well",
                                  times: [5, 20, 70, 130],
                                  pauses: [SessionPause(at: 30, length: 95)],
                                  about: "53 minutes, telehealth")
        XCTAssertEqual(file.text, """
            Transcript, 53 minutes, telehealth
            De-identified by Soapcap, which is best effort: read it through before sharing it.

            [00:00]
            Therapist: hi

            Client: hello

            [Paused for 1 minute, 35 seconds]

            [01:00]
            Therapist: go on

            [02:00]
            Client: well

            """)
    }

    func testATranscriptWithNoTimesGoesInAsItIs() {
        let file = TranscriptFile(transcript: "Therapist: hi\nClient: hello", times: [], pauses: [], about: "1 minute, telehealth")
        XCTAssertTrue(file.text.hasSuffix("\n\nTherapist: hi\nClient: hello\n"), file.text)
    }

    func testItIsPlainTextAndItsNameSaysNothingOfTheSession() {
        XCTAssertEqual(TranscriptFile.readableContentTypes, [.plainText])
        XCTAssertEqual(TranscriptFile.name, "Transcript")
    }
}
