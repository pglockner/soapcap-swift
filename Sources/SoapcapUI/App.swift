import AppKit
import SoapcapCore
import SwiftUI

/// Holds the app open at quit just long enough to stop a note model the
/// app started, so no model server is left running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var beforeQuit: (() async -> Void)?

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
        WindowGroup("soapcap session") {
            ContentView().environmentObject(model)
                .frame(minWidth: 560, minHeight: 420)
                .onReceive(ModelSetup.shared.$state) { state in
                    if state == .ready { Task { @MainActor in model.refreshDeidentify() } }
                }
                .task { AppDelegate.beforeQuit = { [model] in await model.draftRun.stop().value } }
                .task { model.setUpIfNeeded() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                AcknowledgementsCommand()
                UninstallCommand(stop: { [model] in await model.draftRun.stop().value })
            }
        }
        Window("Acknowledgements", id: "acknowledgements") { AcknowledgementsView() }
        Settings { SettingsView() }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch m.phase {
            case .idle: idle
            case .recording: recording
            case .paused: paused
            case .working(let msg): WorkingView(message: msg, run: m.draftRun, stop: { m.stopDraft() })
            case .transcript: transcript
            case .note: note
            case .error(let msg): error(msg)
            case .checks(let checks):
                ChecksView(checks: checks, perform: { m.perform($0) }, reopen: { m.reopen() },
                           again: { m.diagnose() }, back: { m.newSession() })
            }
        }
        // Against the top left however wide the window is; a screen narrower
        // than the window would otherwise float in the middle.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to record").font(.title2.bold())
            Text("Use headphones, and turn on Do Not Disturb.").foregroundStyle(.secondary)
            if m.canDeidentify {
                Toggle("De-identify the transcript, and the note once it's drafted", isOn: $m.deidentify)
            }
            HStack {
                Button("Start recording") { m.start() }.keyboardShortcut(.defaultAction)
                Button("Check permissions") { m.diagnose() }
            }
            Spacer()
        }
    }

    private var recording: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack { Circle().fill(.red).frame(width: 12, height: 12)
                Text(String(format: "recording  %02d:%02d", m.elapsed / 60, m.elapsed % 60))
                    .font(.system(.title2, design: .monospaced)) }
            HStack {
                Button("Pause") { m.pause() }
                Button("Stop") { m.stop() }.keyboardShortcut(.defaultAction)
            }
            Spacer()
            LiveStrip(lines: m.liveLines)
        }.frame(maxWidth: .infinity)
    }

    private var paused: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack { Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text(String(format: "paused  %02d:%02d recorded", m.elapsed / 60, m.elapsed % 60))
                    .font(.system(.title2, design: .monospaced)) }
            Text("Nothing is being captured.").foregroundStyle(.secondary)
            HStack {
                Button("Resume") { m.resume() }.keyboardShortcut(.defaultAction)
                Button("Stop") { m.stop() }
            }
            Spacer()
            LiveStrip(lines: m.liveLines).opacity(0.5)
        }.frame(maxWidth: .infinity)
    }

    private func scrollText(_ s: String) -> some View {
        ScrollView { Text(s).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
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
            Text("Transcript").font(.headline)
            warning
            scrollText(m.transcript)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            // Memory changes as apps open and close, so this is asked again every few seconds.
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                if let advice = m.memoryAdvice {
                    Label(advice, systemImage: "memorychip").font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Picker("Format", selection: $m.format) {
                    ForEach(SessionModel.formats, id: \.self) { Text($0) }
                }.pickerStyle(.segmented).frame(width: 220)
                Button("Draft note") { m.draftIfRoom() }.keyboardShortcut(.defaultAction)
                Spacer()
                Button("New session") { m.newSession() }
            }
        }
        .alert("Not enough free memory", isPresented: Binding(get: { m.memoryQuestion != nil }, set: { if !$0 { m.memoryQuestion = nil } })) {
            // Return should not start a draft the Mac has no room for.
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
            Button("Draft anyway") { m.draft() }
        } message: {
            Text(m.memoryQuestion ?? "")
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(m.format.uppercased()) note").font(.headline)
            warning
            scrollText(m.note)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(m.copied ? "Copied" : "Keep (copy)") { m.keep() }.keyboardShortcut(.defaultAction)
                Button("Regenerate") { m.draft() }
                Spacer()
                // Once the note is on the clipboard, leaving is no longer throwing it away.
                Button(m.copied ? "New session" : "Discard") { m.newSession() }
            }
        }
    }

    private func error(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView { Text(msg).font(.system(.body, design: .monospaced)).foregroundStyle(.orange)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Back") { m.newSession() }
                Button("Check permissions") { m.diagnose() }
            }
        }
    }
}
