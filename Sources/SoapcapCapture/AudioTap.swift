import AVFoundation
import CoreAudio

/// A Core Audio tap: a copy of the sound some apps send to the Mac's output,
/// delivered as buffers. It needs macOS's System Audio Recording Only
/// permission, which has nothing to do with the screen.
///
/// What this relies on, as seen on macOS 27:
/// - macOS asks the first time a tap is listened to, and `start` waits for
///   the answer. Allow counts at once; the app need not be reopened.
/// - A refusal is not an error. Buffers arrive as usual and hold silence,
///   and macOS does not ask again.
/// - Buffers arrive without a gap whether or not anything is playing, always
///   in the same format, and carry on when the output moves to another
///   device (AirPods connecting, in or out of their call mode).
final class AudioTap: @unchecked Sendable {
    private let system = AudioHardwareSystem.shared
    /// Starting and stopping happen here, one at a time.
    private let queue = DispatchQueue(label: "soapcap.audio-tap")
    /// Buffers arrive here. Core Audio hands each one over and waits for it
    /// to be dealt with, so on the queue above a stop could be waiting for a
    /// buffer that is waiting for the stop.
    private let delivery = DispatchQueue(label: "soapcap.audio-tap.buffers")
    private var tap: AudioHardwareTap?
    private var device: AudioHardwareAggregateDevice?
    private var proc: AudioDeviceIOProcID?

    /// Whose sound a tap copies.
    enum Sound: Sendable {
        /// What every app but this one is playing.
        case everythingElse
        /// What this app alone is playing, kept from the speakers while the tap exists.
        case ownSilenced
    }

    deinit { close() }

    /// Starts handing `sound` to `onBuffer`. A buffer is only good until
    /// `onBuffer` returns.
    func start(_ sound: Sound, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            queue.async { done.resume(with: Result { try self.open(sound, onBuffer) }) }
        }
    }

    func stop() async {
        await withCheckedContinuation { done in queue.async { self.close(); done.resume() } }
    }

    private func description(of sound: Sound) -> CATapDescription {
        let own = (try? system.process(for: getpid())).map { [$0.id] } ?? []
        let description: CATapDescription
        switch sound {
        case .everythingElse:
            description = CATapDescription(monoGlobalTapButExcludeProcesses: own)
        case .ownSilenced:
            description = CATapDescription(monoMixdownOfProcesses: own)
            description.muteBehavior = .muted
        }
        description.isPrivate = true
        return description
    }

    private func open(_ sound: Sound, _ onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        close()
        do {
            guard let tap = try system.makeProcessTap(description: description(of: sound)) else { throw CaptureError.callAudioFailed("no tap") }
            self.tap = tap
            var layout = try tap.format
            guard let format = AVAudioFormat(streamDescription: &layout) else { throw CaptureError.callAudioFailed("no format") }
            // The tap is the device's only input. With an output device
            // beside it, that device's own microphone, if it has one, comes
            // first in every buffer list.
            guard let device = try system.makeAggregateDevice(description: [
                kAudioAggregateDeviceNameKey: "Soapcap",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: try tap.uid, kAudioSubTapDriftCompensationKey: true]],
            ]) else { throw CaptureError.callAudioFailed("no device") }
            self.device = device
            // This is the call that waits for the permission question.
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device.id, delivery) { _, input, _, _, _ in
                if let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input) { onBuffer(buffer) }
            }
            guard status == noErr, let proc else { throw CaptureError.callAudioFailed("error \(status)") }
            try device.start(IOProcID: proc)
        } catch {
            close()
            throw error as? CaptureError ?? CaptureError.callAudioFailed(error.localizedDescription)
        }
    }

    private func close() {
        if let device, let proc {
            try? device.stop(IOProcID: proc)
            AudioDeviceDestroyIOProcID(device.id, proc)
        }
        if let device { try? system.destroyAggregateDevice(device) }
        if let tap { try? system.destroyProcessTap(tap) }
        proc = nil
        device = nil
        tap = nil
    }
}
