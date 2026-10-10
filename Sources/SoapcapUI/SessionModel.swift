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
    /// How full memory is, while a note is being drafted; nil otherwise.
    @Published var memory: MemoryStatus?

    /// Whether the de-identification model is installed, so the toggle is offered.
    @Published private(set) var canDeidentify = false
    let settings: SessionSettings
    /// The labels this session was recorded with; Settings may change mid-session.
    private var labels = (mic: "", system: "")
    private let makeCapture: () -> Capturing
    private let now: () -> Date
    private let gatherChecks: () async -> [Check]
    private let readMemory: () -> MemoryStatus?
    private let drafting: Drafting
    private let deidentifying: Deidentifying
    private var isDrafting = false
    private var draftTask: Task<Void, Never>?
    private var capture: Capturing?
    private var recordedBefore: TimeInterval = 0
    private var runStart: Date?
    private var timer: Timer?
    /// Bumped by newSession() so work that finishes afterwards is ignored.
    private var generation = 0

    init(makeCapture: @escaping () -> Capturing = { CaptureSession() }, now: @escaping () -> Date = Date.init,
         settings: SessionSettings = SessionSettings(), drafting: Drafting? = nil,
         deidentifying: Deidentifying? = nil, memory: @escaping () -> MemoryStatus? = MemoryStatus.current,
         checks: (() async -> [Check])? = nil) {
        self.makeCapture = makeCapture
        self.now = now
        self.settings = settings
        self.drafting = drafting ?? ModelDrafting(settings: settings)
        self.deidentifying = deidentifying ?? ModelDeidentifying()
        readMemory = memory
        gatherChecks = checks ?? {
            await Readiness.checks(locale: settings.locale)
                + [await ModelCatalog.check(settings.noteModel, host: settings.ollamaHost)] + [ModelSetup.check()]
                + [Self.memoryCheck(memory(), model: settings.noteModel)]
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

    /// The line on the checks screen.
    static func memoryCheck(_ memory: MemoryStatus?, model: String) -> Check {
        guard let memory else { return Check("Memory", .warning, "Couldn't read how much memory this Mac has.") }
        let size = String(format: "%.0f GB, about %.0f GB free now.", memory.totalGB, memory.availableGB.rounded(.down))
        if let advice = ModelCatalog.memoryAdvice(for: model, memory: memory) { return Check("Memory", .warning, size + " " + advice) }
        return Check("Memory", .ok, size)
    }

    func draft() {
        guard let noteFormat = NoteFormat(rawValue: format) else { return }
        let gen = generation
        draftTask = Task {
            phase = .working("Drafting a \(format) note…")
            isDrafting = true
            // A model that outgrows memory slows to a crawl; show it happening.
            let watch = Task {
                while !Task.isCancelled, gen == generation {
                    memory = readMemory()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            defer { watch.cancel(); memory = nil }
            let drafted: DraftedNote
            do {
                drafted = try await drafting.draft(format: noteFormat, transcript: transcript, minutes: elapsed / 60,
                                                   systemLabel: labels.system) { progress in
                    Task { @MainActor in self.show(progress, generation: gen) }
                }
            } catch {
                isDrafting = false
                // Don't leave a half-started model holding memory (or, for
                // Bonsai, its port) behind an error screen.
                await releaseModel()
                if gen == generation { phase = .error("Note drafting failed.\n\n\(error.localizedDescription)") }
                return
            }
            isDrafting = false
            guard gen == generation else { return }
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

    /// Progress arrives from the drafter's own thread, possibly after the
    /// draft is over; only a draft still in flight may change the screen.
    private func show(_ progress: DraftProgress, generation gen: Int) {
        guard isDrafting, gen == generation else { return }
        phase = .working(progress.tokens.map { "\(progress.title)  \($0) tokens" } ?? progress.title)
    }

    /// Frees the note model's memory; it is kept loaded between drafts.
    func releaseModel() async { await drafting.release() }

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

    func newSession() {
        generation += 1
        timer?.invalidate(); timer = nil
        runStart = nil
        if let capture { Task { _ = await capture.stop() } }
        capture = nil
        isDrafting = false
        draftTask?.cancel(); draftTask = nil
        Task { await releaseModel() }
        liveLines = []; transcript = ""; note = ""; notice = ""; warning = ""; copied = false; memory = nil; phase = .idle
        refreshDeidentify()
    }
}
