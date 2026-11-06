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
        return format(of: layout)
    }

    /// More than 2 channels makes a format only with a channel layout. A
    /// Mac's own microphone has 3 while a call app such as FaceTime uses it.
    static func format(of description: AudioStreamBasicDescription) -> AVAudioFormat? {
        var description = description
        guard description.mChannelsPerFrame > 2 else { return AVAudioFormat(streamDescription: &description) }
        guard let channels = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | description.mChannelsPerFrame) else { return nil }
        return AVAudioFormat(streamDescription: &description, channelLayout: channels)
    }

    /// Whether `device` is the Mac's own speakers: built in, and playing
    /// through its internal speaker rather than headphones. Bluetooth, USB
    /// and display audio never count, since headphones there can't be told
    /// from speakers.
    static func isMacSpeakers(_ device: AudioObjectID) -> Bool {
        func read(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = address(selector, scope: scope)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        guard device != none else { return false }
        return read(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal) == kAudioDeviceTransportTypeBuiltIn
            && read(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput) == internalSpeaker
    }

    /// The data source a Mac's speakers report ('ispk'); headphones are 'hdpn'.
    private static let internalSpeaker: UInt32 = 0x6973_706B
}
