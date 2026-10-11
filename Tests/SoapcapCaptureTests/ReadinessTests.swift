import AVFoundation
import SoapcapCore
import XCTest
@testable import SoapcapCapture

final class ReadinessTests: XCTestCase {
    func testMicrophoneStatusMapsToACheck() {
        XCTAssertEqual(Readiness.microphone(.authorized).status, .ok)
        XCTAssertEqual(Readiness.microphone(.notDetermined).status, .warning)
        XCTAssertEqual(Readiness.microphone(.notDetermined).fix?.action, .askForMicrophone)
        let denied = Readiness.microphone(.denied)
        XCTAssertEqual(denied.status, .failed)
        XCTAssertEqual(denied.fix?.action, .open(Readiness.pane("Privacy_Microphone")))
        XCTAssertEqual(Readiness.microphone(.restricted).status, .failed)
    }

    func testCallAudioWithoutTheGrantPointsAtScreenRecording() {
        XCTAssertEqual(Readiness.callAudio(granted: true).status, .ok)
        let off = Readiness.callAudio(granted: false)
        XCTAssertEqual(off.status, .failed)
        XCTAssertEqual(off.fix?.action, .askForCallAudio)
        XCTAssertTrue(Readiness.callAudioPane.absoluteString.hasSuffix("Privacy_ScreenCapture"))
    }

    func testAnUnsupportedLanguageFails() async {
        let checks = await Readiness.speech(locale: Locale(identifier: "tlh"))
        XCTAssertEqual(checks.map(\.status), [.failed])
    }

    func testEnglishIsRecognized() async {
        let checks = await Readiness.speech(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(checks.count, 1)
        XCTAssertNotEqual(checks[0].status, .failed)
    }
}
