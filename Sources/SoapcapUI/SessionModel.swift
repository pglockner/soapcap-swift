import AppKit
import SoapcapCapture
import SoapcapCore
import SwiftUI

/// What the session needs from audio capture; `CaptureSession` in the app,
/// a scripted stand-in in tests and previews.
protocol Capturing: AnyObject {
    var live: AsyncStream<LiveLine> { get }
    func start(micLabel: String, systemLabel: String) async throws
    func pause()
    func resume()
    func stop() async -> [Segment]
}

extension CaptureSession: Capturing {
    func start(micLabel: String, systemLabel: String) async throws {
        try await start(micLabel: micLabel, systemLabel: systemLabel,
                        locale: Locale(identifier: Locale.current.identifier))
    }
}

@MainActor
final class SessionModel: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, paused, working(String), transcript, note, error(String), checks([Check])
    }

    static let formats = ["soap", "dap", "birp"]
    static let micLabel = "Therapist"
    static let systemLabel = "Client"
    /// How many lines the recording screen's live strip keeps.
    static let liveLimit = 12

    @Published var phase: Phase = .idle
    @Published var deidentify = true
    @Published var format = "soap"
    @Published var transcript = ""
    @Published var note = ""
    @Published var notice = ""
    @Published var elapsed = 0      // seconds recorded; stands still while paused
    @Published var liveLines: [LiveLine] = []
    @Published var copied = false

    let canDeidentify = Runner.deidentifyAvailable
    private let makeCapture: () -> Capturing
    private let now: () -> Date
    private let gatherChecks: () async -> [Check]
    private var capture: Capturing?
    private var recordedBefore: TimeInterval = 0
    private var runStart: Date?
    private var timer: Timer?
    /// Bumped by newSession() so work that finishes afterwards is ignored.
    private var generation = 0

    init(makeCapture: @escaping () -> Capturing = { CaptureSession() }, now: @escaping () -> Date = Date.init,
         checks: @escaping () async -> [Check] = { await Readiness.checks() + Runner.checks }) {
        self.makeCapture = makeCapture
        self.now = now
        gatherChecks = checks
    }

    func start() {
        guard phase == .idle else { return }
        notice = ""; copied = false; liveLines = []; recordedBefore = 0; elapsed = 0
        phase = .working("Starting…")
        let capture = makeCapture()
        self.capture = capture
        let gen = generation
        Task {
            do { try await capture.start(micLabel: Self.micLabel, systemLabel: Self.systemLabel) } catch {
                guard gen == generation else { return }
                self.capture = nil
                phase = .error(error.localizedDescription); return
            }
            guard gen == generation else { _ = await capture.stop(); return }
            run()
            for await line in capture.live where gen == generation { heard(line) }
        }
    }

    private func run() {
        runStart = now()
        phase = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func halt() {
        if let runStart { recordedBefore += now().timeIntervalSince(runStart) }
        runStart = nil
        timer?.invalidate(); timer = nil
        elapsed = Int(recordedBefore)
    }

    func tick() {
        elapsed = Int(recordedBefore + (runStart.map { now().timeIntervalSince($0) } ?? 0))
    }

    /// Nothing is heard while paused, and the clock stands still.
    func pause() {
        guard phase == .recording else { return }
        capture?.pause()
        halt()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        capture?.resume()
        run()
    }

    func stop() {
        guard phase == .recording || phase == .paused, let capture else { return }
        halt()
        phase = .working("Finishing transcription…")
        let gen = generation
        Task {
            let segments = await capture.stop()
            guard gen == generation else { return }
            self.capture = nil
            await finalize(segments)
        }
    }

    /// Folds a line into the live strip: a speaker's in-progress line is
    /// replaced by each newer one until it is final.
    func heard(_ line: LiveLine) {
        if let i = liveLines.lastIndex(where: { $0.speaker == line.speaker && !$0.isFinal }) {
            liveLines[i] = line
        } else {
            liveLines.append(line)
        }
        if liveLines.count > Self.liveLimit { liveLines.removeFirst(liveLines.count - Self.liveLimit) }
    }

    private func finalize(_ segments: [Segment]) async {
        transcript = Transcript.render(segments, mic: Self.micLabel, system: Self.systemLabel)
        guard !transcript.isEmpty else {
            phase = .error("No speech was captured.\n\nUse Check permissions to see whether Soapcap can use the microphone and hear the call.")
            return
        }
        let oneSided = Transcript.oneSidedNotice(segments, mic: Self.micLabel, system: Self.systemLabel) ?? ""
        notice = oneSided
        if deidentify && canDeidentify {
            phase = .working("De-identifying the transcript…")
            let d = await Runner.pipe(["deidentify"], input: transcript)
            if d.status == 0 {
                transcript = d.out.trimmingCharacters(in: .newlines)
                notice = [oneSided, "transcript: \(d.err)"].filter { !$0.isEmpty }.joined(separator: "\n")
            } else {
                notice = [oneSided, "transcript de-identify failed; continuing with the original"]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        phase = .transcript
    }

    func draft() {
        Task {
            phase = .working("Drafting a \(format) note…")
            let n = await Runner.pipe(["note", "--format", format], input: transcript)
            guard n.status == 0, !n.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                phase = .error("Note drafting failed.\n\n\(n.err)"); return
            }
            note = n.out.trimmingCharacters(in: .newlines)
            notice = ""
            if deidentify && canDeidentify {
                let d = await Runner.pipe(["deidentify"], input: note)
                if d.status == 0 {
                    note = d.out.trimmingCharacters(in: .newlines); notice = "note: \(d.err)"
                } else {
                    notice = "note de-identify failed; showing as drafted"
                }
            }
            copied = false
            phase = .note
        }
    }

    func keep() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note, forType: .string)
        // Convention (nspasteboard.org) asking clipboard managers not to record this.
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
    }

    /// Reports what this app can do: its own permissions and speech
    /// recognition, and whether the soapcap tool it still relies on is there.
    func diagnose() {
        let gen = generation
        Task {
            phase = .working("Checking…")
            let checks = await gatherChecks()
            if gen == generation { phase = .checks(checks) }
        }
    }

    func newSession() {
        generation += 1
        timer?.invalidate(); timer = nil
        runStart = nil
        if let capture { Task { _ = await capture.stop() } }
        capture = nil
        liveLines = []; transcript = ""; note = ""; notice = ""; copied = false; phase = .idle
    }
}
