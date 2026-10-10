import AVFoundation
import SoapcapCore
import XCTest
@testable import SoapcapCapture

final class ReadinessTests: XCTestCase {
    func testMicrophoneStatusMapsToACheck() {
        XCTAssertEqual(Readiness.microphone(.authorized).status, .ok)
        XCTAssertEqual(Readiness.microphone(.notDetermined).status, .warning)
        XCTAssertNil(Readiness.microphone(.notDetermined).fix)
        let denied = Readiness.microphone(.denied)
        XCTAssertEqual(denied.status, .failed)
        XCTAssertTrue(denied.fix?.url.absoluteString.hasSuffix("Privacy_Microphone") ?? false)
        XCTAssertEqual(Readiness.microphone(.restricted).status, .failed)
    }

    func testCallAudioWithoutTheGrantPointsAtScreenRecording() {
        XCTAssertEqual(Readiness.callAudio(granted: true).status, .ok)
        let off = Readiness.callAudio(granted: false)
        XCTAssertEqual(off.status, .failed)
        XCTAssertTrue(off.fix?.url.absoluteString.hasSuffix("Privacy_ScreenCapture") ?? false)
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
