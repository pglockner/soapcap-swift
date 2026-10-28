import AppKit
import SoapcapCore
import SwiftUI

/// Holds the app open at quit just long enough to stop a note model the
/// app started, so no model server is left running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var beforeQuit: (() async -> Void)?

    /// Nothing an earlier run fetched is kept, nor anything an earlier
    /// version left that this one no longer uses.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let uninstaller = Uninstaller()
        uninstaller.removeCache()
        uninstaller.removeRetired()
    }

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
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
                AcknowledgementsCommand()
            }
            HelpCommands()
        }
        Window("Acknowledgements", id: "acknowledgements") { AcknowledgementsView() }
        Window("Soapcap Help", id: HelpView.window) { HelpView() }
            .defaultSize(width: 800, height: 600)
        Window("Report a Problem", id: ProblemReportView.window) { ProblemReportView() }
            .windowResizability(.contentSize)
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
