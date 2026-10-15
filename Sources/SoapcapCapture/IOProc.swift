import CoreAudio
import Foundation

/// A block Core Audio calls with a device's buffers, from the moment it is
/// made until `stop`. Making and starting it, and stopping and destroying
/// it, are one step each here, for the call's tap, the microphone and the
/// tone alike. Where a stop happens is still the owner's business: Core
/// Audio waits for a block in progress, so it must never be on the queue
/// the block runs on.
final class IOProc {
    /// What Core Audio said when the block couldn't be made or started.
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "error \(status)" }
    }

    private let device: AudioObjectID
    private var id: AudioDeviceIOProcID?

    /// Starts `block` on `device`, its buffers handed over on `queue`. On a
    /// failure nothing is left behind.
    init(device: AudioObjectID, queue: DispatchQueue, block: @escaping AudioDeviceIOBlock) throws {
        var id: AudioDeviceIOProcID?
        let made = AudioDeviceCreateIOProcIDWithBlock(&id, device, queue, block)
        guard made == noErr, let id else { throw Failure(status: made) }
        let started = AudioDeviceStart(device, id)
        guard started == noErr else {
            AudioDeviceDestroyIOProcID(device, id)
            throw Failure(status: started)
        }
        self.device = device
        self.id = id
    }

    /// Stops the block and destroys it. Only the first call does anything.
    func stop() {
        guard let id else { return }
        self.id = nil
        AudioDeviceStop(device, id)
        AudioDeviceDestroyIOProcID(device, id)
    }

    deinit { stop() }
}
