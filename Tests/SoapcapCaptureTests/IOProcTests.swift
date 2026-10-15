import CoreAudio
import XCTest
@testable import SoapcapCapture

/// The block that hands a device's buffers over, on this Mac's own output.
/// It writes silence, which needs no permission, makes no sound, and is
/// mixed in beside whatever else is playing.
final class IOProcTests: XCTestCase {
    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.withLock { value += 1 } }
        var now: Int { lock.withLock { value } }
    }

    private func waitFor(_ what: String, seconds: Double = 2, _ done: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(done(), "waited \(seconds) s for \(what)")
    }

    func testTheBlockIsCalledUntilStoppedAndStoppingTwiceIsHarmless() async throws {
        let device = AudioDevice.default(.output)
        try XCTSkipIf(device == AudioDevice.none, "this Mac has no output device")
        let calls = Count()
        let proc = try IOProc(device: device, queue: DispatchQueue(label: "soapcap.tests.ioproc")) { _, _, _, output, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            calls.add()
        }
        await waitFor("the first buffers") { calls.now > 2 }
        proc.stop()
        let atStop = calls.now
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(calls.now, atStop, "the block ran after stop")
        proc.stop()
    }

    func testADeviceThatIsntThereFailsAndSaysWhatCoreAudioSaid() {
        XCTAssertThrowsError(try IOProc(device: AudioDevice.none, queue: .main) { _, _, _, _, _ in }) { error in
            let failure = error as? IOProc.Failure
            XCTAssertNotNil(failure)
            XCTAssertNotEqual(failure?.status, noErr)
            XCTAssertEqual(failure?.errorDescription, "error \(failure?.status ?? 0)")
        }
    }
}
