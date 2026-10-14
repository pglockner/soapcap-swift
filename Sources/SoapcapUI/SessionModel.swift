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

    /// The three steps of a session, as the bar across the window shows them.
    enum Stage: Int, CaseIterable { case record, transcript, note }

    nonisolated static let formats = ["soap", "dap", "birp"]
    /// How many lines the recording screen's live strip keeps.
    static let liveLimit = 12

    @Published var phase: Phase = .idle {
        didSet {
            modelTest.isBlocked = phase == .recording || phase == .paused
            switch phase {
            case .idle, .recording, .paused: stage = .record
            case .transcript: stage = .transcript
            case .note: stage = .note
            case .working, .error, .checks: break       // wherever the session had got to
            }
        }
    }
    @Published var format: String { didSet { settings.format = format } }
    /// The step the session has reached, or has been taken back to. It
    /// follows the screen, and runs ahead of it while a step's work is done.
    @Published private(set) var stage: Stage = .record
    @Published var transcript = ""
    /// When each line of the transcript began, in seconds of the session heard.
    @Published var lineTimes: [Int] = []
    /// Each pause in the session: where it fell and how long it lasted.
    @Published var pauses: [SessionPause] = []
    /// Whether the transcript on hand was de-identified, and that step
    /// succeeded. Only then is saving it to a file offered, and a note
    /// drafted from it is de-identified in turn.
    @Published var transcriptIsDeidentified = false
    @Published var note = ""
    /// What stands under the transcript or the note, whichever is on screen.
    @Published var notice = ""
    /// Set when de-identifying was asked for and failed: what is on screen
    /// still has names in it.
    @Published var warning = ""
    @Published var elapsed = 0      // seconds recorded; stands still while paused
    @Published var liveLines: [LiveLine] = []
    @Published var copied = false
    /// The steps the draft in flight has been through, the last of them still
    /// going, and how much the model has written in that one when it says.
    @Published var draftSteps: [String] = []
    @Published var draftTokens: Int?
    /// The format the note on hand was drafted in; the picker may have moved since.
    @Published private(set) var draftedFormat = ""
    /// Set when a draft was asked for with memory very short: the question
    /// to put before going ahead. Cleared by the answer.
    @Published var memoryQuestion: String?
    /// The note model: whether it is working, and the memory in use meanwhile.
    let draftRun: DraftRun
    /// Trying the note model on the sample session, from Settings or the checks screen.
    let modelTest: ModelTest

    /// Whether something stands in the way of a session or its note, as of
    /// the last time the checks were gathered: when the app opened, or
    /// whenever Check was last chosen.
    @Published var needsAttention = false
    /// Whether the de-identification model is installed, so De-identify is offered.
    @Published private(set) var canDeidentify = false
    let settings: SessionSettings
    /// The labels this session was recorded with; Settings may change mid-session.
    private var labels = (mic: "", system: "")
    private let pasteboard: NSPasteboard
    private let makeCapture: () -> Capturing
    private let now: () -> Date
    private let gatherChecks: () async -> [Check]
    private let readMemory: () -> MemoryStatus?
    private let fixer: Fixer
    private let deidentifying: Deidentifying
    private var capture: Capturing?
    private var recordedBefore: TimeInterval = 0
    private var runStart: Date?
    /// When the pause in hand began, by the clock on the wall.
    private var pausedSince: Date?
    private var timer: Timer?
    /// Bumped by newSession() so work that finishes afterwards is ignored.
    private var generation = 0
    /// Whose `notice` and `warning` are on screen, and the other's meanwhile:
    /// the transcript can be gone back to once there is a note.
    private var showing: Stage = .transcript
    private var kept: [Stage: (notice: String, warning: String)] = [:]
    /// Where the draft in flight was asked for, to go back to if it is stopped.
    private var draftedFrom: Stage = .transcript

    /// `pasteboard` is where Keep puts the note. Tests give one of their
    /// own: the real one belongs to whoever is at the Mac.
    init(pasteboard: NSPasteboard = .general,
         makeCapture: @escaping () -> Capturing = { CaptureSession() }, now: @escaping () -> Date = Date.init,
         settings: SessionSettings = SessionSettings(), drafting: Drafting? = nil,
         deidentifying: Deidentifying? = nil, memory: @escaping () -> MemoryStatus? = MemoryStatus.current,
         fixer: Fixer = Fixer(), checks: (() async -> [Check])? = nil) {
        self.pasteboard = pasteboard
        self.fixer = fixer
        self.makeCapture = makeCapture
        self.now = now
        self.settings = settings
        draftRun = DraftRun(drafting: drafting ?? ModelDrafting(settings: settings), memory: memory)
        modelTest = ModelTest(run: draftRun, settings: settings)
        self.deidentifying = deidentifying ?? ModelDeidentifying()
        readMemory = memory
        gatherChecks = checks ?? {
            await Readiness.checks(locale: settings.locale)
                + [await ModelCatalog.check(settings.noteModel, host: settings.ollamaHost)] + [ModelSetup.check()]
                + [ModelCatalog.memoryCheck(memory(), model: settings.noteModel)]
        }
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
        modelTest.stop()        // a session has the Mac to itself
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
        pauses.append(SessionPause(at: elapsed))
        pausedSince = now()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        endPause()
        capture?.resume()
        run()
    }

    /// Notes how long the pause in hand lasted, as it ends. The session's
    /// clock stood still meanwhile, so this is the only record of it.
    private func endPause() {
        guard let pausedSince, !pauses.isEmpty else { return }
        pauses[pauses.count - 1].length = Int(now().timeIntervalSince(pausedSince))
        self.pausedSince = nil
    }

    func stop() {
        guard phase == .recording || phase == .paused, let capture else { return }
        endPause()
        halt()
        phase = .working("Finishing transcription…")
        let gen = generation
        Task {
            let segments = await capture.stop()
            guard gen == generation else { return }
            self.capture = nil
            finalize(segments)
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

    private func finalize(_ segments: [Segment]) {
        let turns = Transcript.turns(segments, mic: labels.mic, system: labels.system)
        transcript = Transcript.render(turns)
        lineTimes = turns.map { Int($0.start) }
        guard !transcript.isEmpty else {
            phase = .error("No speech was captured.\n\nUse Check permissions to see whether Soapcap can use the microphone and hear the call.")
            return
        }
        notice = Transcript.oneSidedNotice(segments, mic: labels.mic, system: labels.system) ?? ""
        phase = .transcript
    }

    /// Replaces names and other identifying details in the transcript, and
    /// in the note as well if one has been drafted, so that the two agree.
    /// Asked for from the transcript, once the session is over.
    func deidentify() {
        guard phase == .transcript, canDeidentify, !transcriptIsDeidentified else { return }
        let gen = generation
        warning = ""
        phase = .working("De-identifying the transcript…")
        Task {
            let d = await deidentified(transcript, kind: .transcript, what: "transcript")
            guard gen == generation else { return }
            if let d {
                transcript = d.text
                transcriptIsDeidentified = true
                tell("Transcript: \(d.summary)")
                if !note.isEmpty {
                    // The note's own banner and notices, while it isn't on screen.
                    put(.note)
                    phase = .working("De-identifying the note…")
                    let n = await deidentified(note, kind: .note, what: "note")
                    guard gen == generation else { return }
                    if let n {
                        // A note kept with its names in it is not the one here now.
                        if n.text != note { note = n.text; copied = false }
                        tell("Note: \(n.summary)")
                    }
                    put(.transcript)
                }
            }
            phase = .transcript
        }
    }

    /// Adds a line to what stands under the transcript or the note.
    private func tell(_ line: String) {
        notice = [notice, line].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The transcript as a text file, for Save transcript.
    var transcriptFile: TranscriptFile {
        TranscriptFile(transcript: transcript, times: lineTimes, pauses: pauses,
                       about: SessionLine.line(minutes: elapsed / 60, type: settings.sessionType))
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
        draftedFrom = stage == .note ? .note : .transcript
        stage = .note
        draftSteps = []; draftTokens = nil
        phase = .working("Drafting a \(format.uppercased()) note…")
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
            draftedFormat = noteFormat.rawValue
            var notices = drafted.warnings
            put(.note)
            warning = ""
            if transcriptIsDeidentified {
                phase = .working("De-identifying the note…")
                let d = await deidentified(note, kind: .note, what: "note")
                guard gen == generation else { return }
                if let d { note = d.text; notices.append("Note: \(d.summary)") }
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
        guard draftRun.isRunning, !modelTest.isRunning else { return }
        generation += 1
        let gen = generation, back = draftedFrom
        let stopping = draftRun.stop()
        phase = .working("Stopping…")
        Task {
            await stopping.value
            if gen == generation { show(back) }
        }
    }

    /// Progress arrives from the drafter's own thread, possibly after the
    /// draft is over; only a draft still in flight may change the screen.
    private func show(_ progress: DraftProgress, generation gen: Int) {
        guard draftRun.isRunning, gen == generation else { return }
        if draftSteps.last != progress.title { draftSteps.append(progress.title) }
        draftTokens = progress.tokens
        phase = .working(progress.tokens.map { "\(progress.title)  \($0) tokens" } ?? progress.title)
    }

    /// Whether there is a note that hasn't been kept. Drafting again would
    /// put another in its place, and no two drafts come out the same.
    var hasUnkeptNote: Bool { !note.isEmpty && !copied }

    /// Whether leaving the session now would lose something: its transcript,
    /// and its note if it has one, until a note has been kept.
    var hasUnkeptWork: Bool { !(transcript.isEmpty && note.isEmpty) && !copied }

    /// Whether the checks can be opened: not while a session is being
    /// transcribed or something is in progress, since they take the screen.
    var canCheck: Bool {
        switch phase {
        case .recording, .paused, .working: false
        default: true
        }
    }

    /// Whether a step in the bar can be clicked: the transcript once there
    /// is a note, and back to the note from there. Recording can't be gone
    /// back to.
    func canGo(to step: Stage) -> Bool {
        switch (step, phase) {
        case (.transcript, .note): true
        case (.note, .transcript): !note.isEmpty
        default: false
        }
    }

    func go(to step: Stage) {
        if canGo(to: step) { show(step) }
    }

    /// Leaves an error or the checks for the session as it stood: its note
    /// or transcript if it has one, or else a fresh start. A draft that
    /// fails must not cost the transcript.
    func back() {
        guard !transcript.isEmpty else { return newSession() }
        show(stage == .note && !note.isEmpty ? .note : .transcript)
    }

    /// Puts the transcript or the note on screen, with what stands under it.
    private func show(_ step: Stage) {
        put(step)
        phase = step == .note ? .note : .transcript
    }

    /// Swaps `notice` and `warning` for those of the transcript or the note.
    private func put(_ step: Stage) {
        guard step != showing else { return }
        kept[showing] = (notice, warning)
        (notice, warning) = kept[step] ?? ("", "")
        showing = step
    }

    func keep() {
        let pb = pasteboard
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
            needsAttention = checks.needAttention
            if gen == generation { phase = .checks(checks) }
        }
    }

    /// What the setup screen's buttons reach outside this window.
    struct Fixer {
        var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
        var askForMicrophone: () async -> Void = { await Readiness.askForMicrophone() }
        var askForCallAudio: () async -> Void = { await Readiness.askForCallAudio() }
    }

    /// Looks the Mac over as the app opens. On a first launch, or after a
    /// permission was taken away, the checks screen is the place to start.
    /// Anything else in the way is left for the Ready screen to point at.
    func setUpIfNeeded() {
        Task {
            let checks = await gatherChecks()
            needsAttention = checks.needAttention
            if checks.lackPermission, phase == .idle { phase = .checks(checks) }
        }
    }

    /// Does what a button on the checks screen stands for.
    func perform(_ action: Check.Fix.Action) {
        switch action {
        case .open(let url):
            fixer.open(url)
        case .askForMicrophone:
            Task { await fixer.askForMicrophone(); diagnose() }      // the answer shows at once
        case .askForCallAudio:
            Task { await fixer.askForCallAudio(); diagnose() }
        case .showSettings:
            break       // the window opens its own Settings
        }
    }

    func newSession() {
        generation += 1
        timer?.invalidate(); timer = nil
        runStart = nil; pausedSince = nil
        if let capture { Task { _ = await capture.stop() } }
        capture = nil
        draftRun.stop()
        liveLines = []; transcript = ""; lineTimes = []; pauses = []; transcriptIsDeidentified = false; note = ""; notice = ""; warning = ""; copied = false; memoryQuestion = nil; phase = .idle
        showing = .transcript; kept = [:]
        refreshDeidentify()
    }
}
