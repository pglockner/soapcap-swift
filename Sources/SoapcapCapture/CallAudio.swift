import AVFoundation
import CoreAudio
import os

/// Whether macOS lets this app hear what the Mac is playing.
public enum CallAudioAccess: Equatable, Sendable {
    /// macOS has not put its question yet, and finding out would put it.
    case notAsked
    case allowed
    case refused
}

/// Finding out whether the app can hear the Mac's audio. macOS has no way to
/// look that permission up, and a refusal sounds exactly like silence, so
/// the app plays itself a tone nobody hears and listens for it.
public enum CallAudio {
    static let askedKey = "callAudioAsked"

    /// The answer, without making macOS ask for the first time.
    public static func access(defaults: UserDefaults = .standard,
                              hears: () async -> Bool = hearsItself) async -> CallAudioAccess {
        guard defaults.bool(forKey: askedKey) else { return .notAsked }
        return await hears() ? .allowed : .refused
    }

    /// Has macOS put its question, the first time, and returns the answer.
    @discardableResult
    public static func ask(defaults: UserDefaults = .standard,
                           hears: () async -> Bool = hearsItself) async -> CallAudioAccess {
        defaults.set(true, forKey: askedKey)
        return await access(defaults: defaults, hears: hears)
    }

    /// True if a tone the app plays comes back through a tap of the app's
    /// own sound. The tap keeps the tone from the speakers. About a fifth of
    /// a second when it is heard, two seconds when it is not.
    public static func hearsItself() async -> Bool {
        let tap = AudioTap(), tone = Tone()
        let heard = OSAllocatedUnfairLock(initialState: false)
        do {
            try await tap.start(.ownSilenced) { buffer in
                guard let samples = buffer.floatChannelData?[0] else { return }
                for i in 0..<Int(buffer.frameLength) where abs(samples[i]) > Tone.level / 2 {
                    heard.withLock { $0 = true }
                    return
                }
            }
        } catch { return false }
        if tone.start() {
            let deadline = Date().addingTimeInterval(2)
            while !heard.withLock({ $0 }), Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        // The tone has to end before the tap that silences it goes.
        tone.stop()
        await tap.stop()
        return heard.withLock { $0 }
    }
}

/// A steady tone on the Mac's output, quiet enough to go unnoticed even if
/// nothing were silencing it. Written straight into the output device, as
/// the microphone is read straight from its own.
private final class Tone {
    static let level: Float = 0.001
    private let queue = DispatchQueue(label: "soapcap.tone")
    private var device = AudioDevice.none
    private var proc: AudioDeviceIOProcID?

    func start() -> Bool {
        let device = AudioDevice.default(.output)
        // Samples are written as 32-bit floats, which is what Core Audio
        // takes from apps for any device it mixes sound for.
        guard let format = AudioDevice.format(of: device, .output), format.commonFormat == .pcmFormatFloat32 else { return false }
        let step = 2 * Float.pi * 440 / Float(format.sampleRate)
        var phase: Float = 0
        var proc: AudioDeviceIOProcID?
        let made = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, _, _, output, _ in
            for (index, buffer) in UnsafeMutableAudioBufferListPointer(output).enumerated() {
                guard let data = buffer.mData else { continue }
                // The tone goes to the device's first stream; any other gets silence.
                guard index == 0 else { memset(data, 0, Int(buffer.mDataByteSize)); continue }
                let channels = max(Int(buffer.mNumberChannels), 1)
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    let sample = Self.level * sin(phase + Float(frame) * step)
                    for channel in 0..<channels { samples[frame * channels + channel] = sample }
                }
                phase = (phase + Float(frames) * step).truncatingRemainder(dividingBy: 2 * .pi)
            }
        }
        guard made == noErr, let proc else { return false }
        guard AudioDeviceStart(device, proc) == noErr else {
            AudioDeviceDestroyIOProcID(device, proc)
            return false
        }
        (self.device, self.proc) = (device, proc)
        return true
    }

    func stop() {
        guard let proc else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        self.proc = nil
    }
}
