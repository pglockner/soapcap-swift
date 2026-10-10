import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Whatever the Mac is playing (the other side of a call), through
/// ScreenCaptureKit. This is why the app needs Screen Recording permission;
/// no picture is kept, the video side is a 2x2 frame once a second.
final class SystemAudioSource: NSObject, AudioSource, SCStreamOutput {
    var onProblem: ((String) -> Void)?
    private var stream: SCStream?
    private var converter: BufferConverter?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        let display: SCDisplay
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let first = content.displays.first else { throw CaptureError.screenRecordingDenied }
            display = first
        } catch { throw CaptureError.screenRecordingDenied }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(format.sampleRate)
        config.channelCount = Int(format.channelCount)
        config.excludesCurrentProcessAudio = true
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        converter = BufferConverter(to: format)
        self.onBuffer = onBuffer
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        do { try await stream.startCapture() } catch { throw CaptureError.screenRecordingDenied }
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sample.isValid, sample.numSamples > 0,
              let description = sample.formatDescription?.audioStreamBasicDescription,
              let source = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                         channels: description.mChannelsPerFrame) else { return }
        try? sample.withAudioBufferList { list, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source, bufferListNoCopy: list.unsafePointer),
                  let converted = converter?.convert(buffer) else { return }
            onBuffer?(converted)
        }
    }
}
