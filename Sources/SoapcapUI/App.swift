import AppKit
import SoapcapCore
import SwiftUI

/// Holds the app open at quit just long enough to stop a note model the
/// app started, so no model server is left running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var beforeQuit: (() async -> Void)?

    /// Nothing an earlier run fetched is kept.
    func applicationWillFinishLaunching(_ notification: Notification) { Uninstaller().removeCache() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let beforeQuit = Self.beforeQuit else { return .terminateNow }
        Task { @MainActor in
            await beforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

public struct SoapcapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SessionModel()

    public init() {}

    public var body: some Scene {
        WindowGroup("Soapcap", id: SessionMenu.window) {
            ContentView().environmentObject(model)
                .frame(minWidth: 560, minHeight: 420)
                .onReceive(ModelSetup.shared.$state) { state in
                    if state == .ready { Task { @MainActor in model.refreshDeidentify() } }
                }
                .task { AppDelegate.beforeQuit = { [model] in await model.draftRun.stop().value } }
                .task { model.setUpIfNeeded() }
        }
        // Tall enough the first time for the setup screen to show every row.
        .defaultSize(width: 640, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                AcknowledgementsCommand()
            }
        }
        Window("Acknowledgements", id: "acknowledgements") { AcknowledgementsView() }
        // The session's time, in the menu bar for as long as a session runs:
        // no window covers it there, as the call's window covers this one.
        MenuBarExtra(isInserted: .constant(model.phase == .recording || model.phase == .paused)) {
            SessionMenu(m: model)
        } label: {
            Label {
                Text(SessionClock.text(model.elapsed)).monospacedDigit()
            } icon: {
                Image(systemName: model.phase == .paused ? "pause.fill" : "microphone.fill")
            }
            .labelStyle(.titleAndIcon)
        }
        Settings { SettingsView(test: model.modelTest, stop: { [model] in await model.draftRun.stop().value }) }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: SessionModel
    /// Read here so that this window follows a change of model made in Settings.
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
    /// Asked before a note that hasn't been kept is drafted over.
    @State private var asksToReplace = false
    /// Whether the panel that saves the transcript is up, and what went
    /// wrong if a save failed.
    @State private var savesTranscript = false
    @State private var saveFailed = false
    @State private var saveFailure = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch m.phase {
            case .idle: idle
            case .recording: recording
            case .paused: paused
            case .working(let msg):
                WorkingView(message: msg, run: m.draftRun, test: m.modelTest, steps: m.draftSteps, tokens: m.draftTokens,
                            keepsEarlierNote: !m.note.isEmpty, stop: { m.stopDraft() })
            case .transcript: transcript
            case .note: note
            case .error(let msg): error(msg)
            case .checks(let checks):
                ChecksView(checks: checks, test: m.modelTest, model: SessionSettings.noteModel(stored: noteModel),
                           perform: { m.perform($0) }, again: { m.diagnose() }, back: { m.back() })
                    // The line about the note model is about the one just chosen.
                    .onChange(of: noteModel) { m.diagnose() }
            }
        }
        // Against the top left however wide the window is; a screen narrower
        // than the window would otherwise float in the middle.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .toolbar { SessionBar(m: m) }
        // The bar says the app's name itself, beside its icon.
        .toolbar(removing: .title)
    }

    /// Laid out as the session it leads to: the clock where it will run, and
    /// what to see to first where the lines heard will appear.
    private var idle: some View {
        VStack(spacing: 16) {
            Spacer()
            SessionClock(title: "Ready for a session", symbol: "microphone", tint: .secondary, elapsed: 0, isWaiting: true)
            HStack {
                Button("Start session") { m.start() }.keyboardShortcut(.defaultAction)
                // Only when the last look over the Mac found something in
                // the way; the bar's Check is there for the rest of the time.
                if m.needsAttention {
                    Button { m.diagnose() } label: {
                        Label {
                            Text("See what needs attention")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            Spacer()
            Text("Use headphones, and turn on Do Not Disturb.").foregroundStyle(.secondary)
                .frame(height: LiveStrip.height)
        }.frame(maxWidth: .infinity)
    }

    private var recording: some View {
        VStack(spacing: 16) {
            Spacer()
            // Nothing is recorded: the app listens, and what it hears becomes text.
            SessionClock(title: "Transcribing", symbol: "microphone.fill", tint: .red, elapsed: m.elapsed, isLive: true)
            HStack {
                Button("Pause") { m.pause() }
                StopButton { m.stop() }
            }
            Spacer()
            LiveStrip(lines: m.liveLines)
        }.frame(maxWidth: .infinity)
    }

    private var paused: some View {
        VStack(spacing: 16) {
            Spacer()
            SessionClock(title: "Paused", symbol: "pause.circle.fill", tint: .orange, elapsed: m.elapsed)
            Text("Nothing is being captured.").foregroundStyle(.secondary)
            HStack {
                Button("Resume") { m.resume() }.keyboardShortcut(.defaultAction)
                StopButton { m.stop() }
            }
            Spacer()
            LiveStrip(lines: m.liveLines).opacity(0.5)
        }.frame(maxWidth: .infinity)
    }

    /// Shown above text that was meant to be de-identified and was not.
    @ViewBuilder private var warning: some View {
        if !m.warning.isEmpty {
            Label(m.warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transcript").font(.headline)
                Spacer()
                // The one thing the app ever writes to disk, and only a
                // transcript that de-identifying has been over: until then,
                // the button in its place is the way to have that done.
                if m.transcriptIsDeidentified {
                    Button("Save transcript…") { savesTranscript = true }
                        .controlSize(.small)
                        .help("Save the de-identified transcript as a text file, wherever you choose")
                } else if m.canDeidentify {
                    Button("De-identify") { m.deidentify() }
                        .controlSize(.small)
                        .help("Replace names and other identifying details with tokens, in the transcript and in the note. Then the transcript can be saved.")
                }
            }
            warning
            TranscriptView(text: m.transcript, times: m.lineTimes, pauses: m.pauses)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            // Memory changes as apps open and close, so this is asked again every few seconds.
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                if let advice = m.memoryAdvice {
                    Label(advice, systemImage: "memorychip").font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Picker("Format", selection: $m.format) {
                    ForEach(SessionModel.formats, id: \.self) { Text($0.uppercased()) }
                }.pickerStyle(.segmented).fixedSize()
                Button(m.hasUnkeptNote ? "Draft again" : "Draft note") {
                    if m.hasUnkeptNote { asksToReplace = true } else { m.draftIfRoom() }
                }
                // Return doesn't draft over a note that hasn't been kept.
                .keyboardShortcut(m.hasUnkeptNote ? nil : .defaultAction)
                .alert("Replace the note you haven't kept?", isPresented: $asksToReplace) {
                    Button("Cancel", role: .cancel) {}
                    Button("Draft again", role: .destructive) { m.draftIfRoom() }
                } message: {
                    Text("Drafting again writes a new note in its place, and the one you have can't be got back. To hold on to it, go to the note and choose Keep first.")
                }
                Spacer()
                LeaveButton(m: m)
            }
        }
        .alert("Not enough free memory", isPresented: Binding(get: { m.memoryQuestion != nil }, set: { if !$0 { m.memoryQuestion = nil } })) {
            // Return should not start a draft the Mac has no room for.
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
            Button("Draft anyway") { m.draft() }
        } message: {
            Text(m.memoryQuestion ?? "")
        }
        .fileExporter(isPresented: $savesTranscript, document: m.transcriptFile, contentType: .plainText,
                      defaultFilename: TranscriptFile.name) { result in
            // Closing the panel without saving is not a failure.
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                saveFailure = error.localizedDescription
                saveFailed = true
            }
        }
        .alert("The transcript was not saved", isPresented: $saveFailed) {} message: {
            Text(saveFailure)
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\((m.draftedFormat.isEmpty ? m.format : m.draftedFormat).uppercased()) note").font(.headline)
            warning
            ReadingText(text: m.note)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(m.copied ? "Copied" : "Keep") { m.keep() }.keyboardShortcut(.defaultAction)
                Button("Regenerate") { m.draft() }
                Spacer()
                LeaveButton(m: m)
            }
        }
    }

    private func error(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Label { Text(msg).textSelection(.enabled) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Back") { m.back() }
                Button("Check permissions") { m.diagnose() }
            }
        }
    }
}

/// Ends a session. A session that is stopped can't be taken up again, so the
/// button is red and Return doesn't press it.
struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button("Stop", action: action).buttonStyle(.borderedProminent).tint(.red)
    }
}

/// Starts afresh. While the session holds something that hasn't been kept it
/// says Discard, in red, and asks first; once the note is on the clipboard,
/// leaving is no longer throwing anything away.
struct LeaveButton: View {
    @ObservedObject var m: SessionModel
    @State private var asks = false

    var body: some View {
        Button {
            if m.hasUnkeptWork { asks = true } else { m.newSession() }
        } label: {
            Text(m.hasUnkeptWork ? "Discard" : "New session").foregroundStyle(m.hasUnkeptWork ? Color.red : Color.primary)
        }
        .alert("Discard this session?", isPresented: $asks) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { m.newSession() }
        } message: {
            Text(m.note.isEmpty ? "The transcript can't be got back." : "The transcript and the note can't be got back. To hold on to the note, choose Keep first.")
        }
    }
}
