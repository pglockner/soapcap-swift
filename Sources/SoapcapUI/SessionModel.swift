import AppKit
import SoapcapCapture
import SoapcapCore
import SoapcapDeidentify
import SoapcapNote
import SwiftUI

@MainActor
final class SessionModel: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, paused, working(String), transcript, note, error(String), checks([Check])
    }

    nonisolated static let formats = ["soap", "dap", "birp"]
    /// How many lines the recording screen's live strip keeps.
    static let liveLimit = 12

    @Published var phase: Phase = .idle
    @Published var deidentify: Bool { didSet { settings.deidentify = deidentify } }
    @Published var format: String { didSet { settings.format = format } }
    @Published var transcript = ""
    @Published var note = ""
    @Published var notice = ""
    /// Set when de-identifying was asked for and failed: what is on screen
    /// still has names in it.
    @Published var warning = ""
    @Published var elapsed = 0      // seconds recorded; stands still while paused
    @Published var liveLines: [LiveLine] = []
    @Published var copied = false
    /// Set when a draft was asked for with memory very short: the question
    /// to put before going ahead. Cleared by the answer.
    @Published var memoryQuestion: String?
    /// The note model: whether it is working, and the memory in use meanwhile.
    let draftRun: DraftRun

    /// Whether the de-identification model is installed, so the toggle is offered.
    @Published private(set) var canDeidentify = false
    let settings: SessionSettings
    /// The labels this session was recorded with; Settings may change mid-session.
    private var labels = (mic: "", system: "")
    private let makeCapture: () -> Capturing
    private let now: () -> Date
    private let gatherChecks: () async -> [Check]
    private let readMemory: () -> MemoryStatus?
    private let fixer: Fixer
    private let deidentifying: Deidentifying
    private var capture: Capturing?
    private var recordedBefore: TimeInterval = 0
    private var runStart: Date?
    private var timer: Timer?
    /// Bumped by newSession() so work that finishes afterwards is ignored.
    private var generation = 0

    init(makeCapture: @escaping () -> Capturing = { CaptureSession() }, now: @escaping () -> Date = Date.init,
         settings: SessionSettings = SessionSettings(), drafting: Drafting? = nil,
         deidentifying: Deidentifying? = nil, memory: @escaping () -> MemoryStatus? = MemoryStatus.current,
         fixer: Fixer = Fixer(), checks: (() async -> [Check])? = nil) {
        self.fixer = fixer
        self.makeCapture = makeCapture
        self.now = now
        self.settings = settings
        draftRun = DraftRun(drafting: drafting ?? ModelDrafting(settings: settings), memory: memory)
        self.deidentifying = deidentifying ?? ModelDeidentifying()
        readMemory = memory
        gatherChecks = checks ?? {
            await Readiness.checks(locale: settings.locale)
                + [await ModelCatalog.check(settings.noteModel, host: settings.ollamaHost)] + [ModelSetup.check()]
                + [ModelCatalog.memoryCheck(memory(), model: settings.noteModel)]
        }
        deidentify = settings.deidentify
        format = settings.format
        canDeidentify = self.deidentifying.isReady
    }

    /// Call when the model may have been installed since the window opened.
    func refreshDeidentify() { canDeidentify = deidentifying.isReady }

    /// Replaces identifying text, or sets `warning` and returns nil: the
    /// session's text is kept, but never shown as if it had been checked.
    private func deidentified(_ text: String, kind: LabeledText.Kind, what: String) async -> Deidentified? {
        do { return try await deidentifying.deidentify(text, kind: kind) } catch {
            warning = "Not de-identified. This \(what) still contains names and other identifying details.\n\(error.localizedDescription)"
            return nil
        }
    }

    func start() {
        guard phase == .idle else { return }
        notice = ""; warning = ""; copied = false; liveLines = []; recordedBefore = 0; elapsed = 0
        phase = .working("Starting…")
        labels = (settings.micLabel, settings.systemLabel)
        let locale = settings.locale
        let capture = makeCapture()
        self.capture = capture
        let gen = generation
        Task {
            do { try await capture.start(micLabel: labels.mic, systemLabel: labels.system, locale: locale) } catch {
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
        transcript = Transcript.render(segments, mic: labels.mic, system: labels.system)
        guard !transcript.isEmpty else {
            phase = .error("No speech was captured.\n\nUse Check permissions to see whether Soapcap can use the microphone and hear the call.")
            return
        }
        let oneSided = Transcript.oneSidedNotice(segments, mic: labels.mic, system: labels.system) ?? ""
        notice = oneSided
        if deidentify && canDeidentify {
            phase = .working("De-identifying the transcript…")
            if let d = await deidentified(transcript, kind: .transcript, what: "transcript") {
                transcript = d.text
                notice = [oneSided, "transcript: \(d.summary)"].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        phase = .transcript
    }

    /// What to do before drafting when the chosen model won't fit in the
    /// memory that is free, or nil. Read afresh each time it is asked.
    var memoryAdvice: String? {
        ModelCatalog.memoryAdvice(for: settings.noteModel, memory: readMemory())
    }

    /// Drafts, unless memory is very short for the chosen model, in which
    /// case it asks first. Not for drafting again: by then the model is
    /// loaded and is itself what fills memory.
    func draftIfRoom() {
        memoryQuestion = ModelCatalog.memoryQuestion(for: settings.noteModel, memory: readMemory())
        if memoryQuestion == nil { draft() }
    }

    func draft() {
        guard let noteFormat = NoteFormat(rawValue: format) else { return }
        let gen = generation
        phase = .working("Drafting a \(format) note…")
        Task {
            let drafted: DraftedNote
            do {
                // Nil when the draft was stopped; stopDraft() has the screen.
                guard let done = try await draftRun.draft(format: noteFormat, transcript: transcript, minutes: elapsed / 60,
                                                          systemLabel: labels.system, progress: { progress in
                    Task { @MainActor in self.show(progress, generation: gen) }
                }), gen == generation else { return }
                drafted = done
            } catch {
                if gen == generation { phase = .error("Note drafting failed.\n\n\(error.localizedDescription)") }
                return
            }
            note = drafted.text
            var notices = drafted.warnings
            if deidentify && canDeidentify {
                phase = .working("De-identifying the note…")
                warning = ""
                let d = await deidentified(note, kind: .note, what: "note")
                guard gen == generation else { return }
                if let d { note = d.text; notices.append("note: \(d.summary)") }
            }
            notice = notices.joined(separator: "\n")
            copied = false
            phase = .note
        }
    }

    /// Gives up on the draft in flight and frees the model's memory, then
    /// goes back to the transcript (or to the note being drafted again).
    /// The screen waits for the model to go, so that another draft can't
    /// start while the first one's model is still shutting down.
    func stopDraft() {
        guard draftRun.isRunning else { return }
        generation += 1
        let gen = generation, back: Phase = note.isEmpty ? .transcript : .note
        let stopping = draftRun.stop()
        phase = .working("Stopping…")
        Task {
            await stopping.value
            if gen == generation { phase = back }
        }
    }

    /// Progress arrives from the drafter's own thread, possibly after the
    /// draft is over; only a draft still in flight may change the screen.
    private func show(_ progress: DraftProgress, generation gen: Int) {
        guard draftRun.isRunning, gen == generation else { return }
        phase = .working(progress.tokens.map { "\(progress.title)  \($0) tokens" } ?? progress.title)
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
    /// recognition, the note model, and de-identification.
    func diagnose() {
        let gen = generation
        Task {
            phase = .working("Checking…")
            let checks = await gatherChecks()
            if gen == generation { phase = .checks(checks) }
        }
    }

    /// What the setup screen's buttons reach outside this window.
    struct Fixer {
        var hasPermissions: () -> Bool = { Readiness.hasPermissions }
        var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
        var askForMicrophone: () async -> Void = { await Readiness.askForMicrophone() }
        var askForCallAudio: () -> Void = { Readiness.askForCallAudio() }
        var reopen: () -> Void = {
            let again = NSWorkspace.OpenConfiguration()
            again.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: again) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    /// On a first launch, or after a permission was taken away, the checks
    /// screen is the place to start.
    func setUpIfNeeded() {
        if phase == .idle, !fixer.hasPermissions() { diagnose() }
    }

    /// Does what a button on the checks screen stands for.
    func perform(_ action: Check.Fix.Action) {
        switch action {
        case .open(let url):
            fixer.open(url)
        case .askForMicrophone:
            Task { await fixer.askForMicrophone(); diagnose() }      // the answer shows at once
        case .askForCallAudio:
            // The first time macOS asks; after that it stays quiet, so the
            // list is opened either way.
            fixer.askForCallAudio()
            fixer.open(Readiness.callAudioPane)
        case .showSettings:
            break       // the window opens its own Settings
        }
    }

    /// Quits and opens the app again, which is when macOS counts a new permission.
    func reopen() { fixer.reopen() }

    func newSession() {
        generation += 1
        timer?.invalidate(); timer = nil
        runStart = nil
        if let capture { Task { _ = await capture.stop() } }
        capture = nil
        draftRun.stop()
        liveLines = []; transcript = ""; note = ""; notice = ""; warning = ""; copied = false; memoryQuestion = nil; phase = .idle
        refreshDeidentify()
    }
}
