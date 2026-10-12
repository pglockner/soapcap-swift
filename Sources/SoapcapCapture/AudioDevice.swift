import AVFoundation
import CoreAudio

/// What the capture code asks Core Audio about the Mac's sound devices.
enum AudioDevice {
    enum Direction {
        case input, output

        var scope: AudioObjectPropertyScope {
            self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        }
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let none = AudioObjectID(kAudioObjectUnknown)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The device sound goes to, or comes from, unless an app picks another.
    static func `default`(_ direction: Direction) -> AudioObjectID {
        var device = none
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(direction == .input ? kAudioHardwarePropertyDefaultInputDevice
                                                  : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
        return device
    }

    /// The format of `device`'s first stream in that direction; nil if it has none.
    static func format(of device: AudioObjectID, _ direction: Direction) -> AVAudioFormat? {
        guard device != none else { return nil }
        var address = address(kAudioDevicePropertyStreams, scope: direction.scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return nil }
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !streams.isEmpty, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return nil }
        var layout = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        address = Self.address(kAudioStreamPropertyVirtualFormat)
        guard AudioObjectGetPropertyData(streams[0], &address, 0, nil, &size, &layout) == noErr,
              layout.mSampleRate > 0, layout.mChannelsPerFrame > 0 else { return nil }
        return AVAudioFormat(streamDescription: &layout)
    }
}
