import AVFoundation
import XCTest
@testable import SoapcapCapture

final class BufferConverterTests: XCTestCase {
    /// A Mac's own microphone has 3 channels while FaceTime uses it. Read
    /// as no microphone at all, and then converted to silence, before.
    func testAThreeChannelMicrophoneIsHeardInMono() throws {
        let description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 12,
            mFramesPerPacket: 1, mBytesPerFrame: 12, mChannelsPerFrame: 3, mBitsPerChannel: 32, mReserved: 0)
        let format = try XCTUnwrap(AudioDevice.format(of: description))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<4800 {
            samples[frame * 3] = 0.5 * sinf(Float(frame) * 0.1)
            samples[frame * 3 + 1] = 0
            samples[frame * 3 + 2] = 0
        }
        let mono = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let out = try XCTUnwrap(BufferConverter(to: mono).convert(buffer))
        let peak = (0..<Int(out.frameLength)).map { abs(Int(out.int16ChannelData![0][$0])) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1000, "the microphone came out silent")
    }
}
