import AudioToolbox
import AVFoundation

/// The default input heard through Apple's voice processing, which takes
/// out what the Mac's speakers play (the call, other apps) before it
/// reaches the microphone's side. Buffers are mono at `sampleRate`, from
/// the moment it is made until `stop`, on Core Audio's own thread; each is
/// only lent for the call, as with `IOProc`.
///
/// Measured on a MacBook Air's own microphone and speakers: about 40 dB
/// less of another app's sound, with a voice spoken over it heard in full.
/// With a USB microphone beside a Mac mini's speaker it was not seen to help.
final class VoiceProcessedInput {
    struct Failure: LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { "voice processing: \(step) failed, error \(status)" }
    }

    /// The most frames Core Audio is allowed to ask for at once.
    private static let maxFrames: UInt32 = 4096
    private let context: VoiceInputContext
    private var unit: AudioUnit?

    /// Starts it on the default input and output. On a failure nothing is left behind.
    init(sampleRate: Double, handler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.maxFrames) else {
            throw Failure(step: "format", status: kAudio_ParamError)
        }
        context = VoiceInputContext(buffer: buffer, handler: handler)
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_VoiceProcessingIO,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw Failure(step: "find", status: kAudio_ParamError) }
        var made: AudioUnit?
        let status = AudioComponentInstanceNew(component, &made)
        guard status == noErr, let made else { throw Failure(step: "make", status: status) }
        // Known to the callback before the unit starts calling it.
        context.unit = made
        do {
            try Self.configure(made, format: format, context: context)
        } catch {
            AudioComponentInstanceDispose(made)
            throw error
        }
        unit = made
    }

    /// Stops it and lets the unit go. Only the first call does anything.
    func stop() {
        guard let unit else { return }
        self.unit = nil
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }

    deinit { stop() }

    private static func configure(_ unit: AudioUnit, format: AVAudioFormat, context: VoiceInputContext) throws {
        func set<T: BitwiseCopyable>(_ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement,
                    _ value: T, _ step: String) throws {
            var value = value
            let status = AudioUnitSetProperty(unit, property, scope, element, &value, UInt32(MemoryLayout<T>.size))
            guard status == noErr else { throw Failure(step: step, status: status) }
        }
        let input: AudioUnitElement = 1, output: AudioUnitElement = 0
        try set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, input, UInt32(1), "enable input")
        // The unit plays as well, and is given silence: the speakers carry
        // only what other apps play, which is what it takes back out.
        try set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, output, UInt32(1), "enable output")
        // Your level stays your own, and the call is not turned down.
        try set(kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, UInt32(0), "gain control off")
        try set(kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
                AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: .min), "ducking off")
        try set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, input, format.streamDescription.pointee, "microphone format")
        try set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, output, format.streamDescription.pointee, "speaker format")
        try set(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, maxFrames, "buffer size")
        let refCon = Unmanaged.passUnretained(context).toOpaque()
        try set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                AURenderCallbackStruct(inputProc: heard, inputProcRefCon: refCon), "microphone callback")
        try set(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, output,
                AURenderCallbackStruct(inputProc: silence, inputProcRefCon: nil), "speaker callback")
        var status = AudioUnitInitialize(unit)
        guard status == noErr else { throw Failure(step: "initialize", status: status) }
        status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            AudioUnitUninitialize(unit)
            throw Failure(step: "start", status: status)
        }
    }
}

/// Fetches the processed microphone samples into the context's buffer and hands it on.
private let heard: AURenderCallback = { refCon, flags, timeStamp, bus, frames, _ in
    let context = Unmanaged<VoiceInputContext>.fromOpaque(refCon).takeUnretainedValue()
    return context.render(flags, timeStamp, bus, frames)
}

/// The unit's own sound: none.
private let silence: AURenderCallback = { _, flags, _, _, _, data in
    guard let data else { return noErr }
    for buffer in UnsafeMutableAudioBufferListPointer(data) {
        if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
    }
    flags.pointee.insert(.unitRenderAction_OutputIsSilence)
    return noErr
}

/// What Core Audio's thread needs: the unit to ask for the microphone's
/// samples, a buffer made in advance to take them, and where they go.
private final class VoiceInputContext {
    var unit: AudioUnit?
    let buffer: AVAudioPCMBuffer
    let list: UnsafeMutablePointer<AudioBufferList>
    let handler: (AVAudioPCMBuffer) -> Void

    init(buffer: AVAudioPCMBuffer, handler: @escaping (AVAudioPCMBuffer) -> Void) {
        self.buffer = buffer
        list = buffer.mutableAudioBufferList
        self.handler = handler
    }

    func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ timeStamp: UnsafePointer<AudioTimeStamp>,
                _ bus: UInt32, _ frames: UInt32) -> OSStatus {
        guard let unit, frames <= buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
        list.pointee.mBuffers.mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
        let status = AudioUnitRender(unit, flags, timeStamp, bus, frames, list)
        guard status == noErr else { return status }
        buffer.frameLength = frames
        handler(buffer)
        return noErr
    }
}
