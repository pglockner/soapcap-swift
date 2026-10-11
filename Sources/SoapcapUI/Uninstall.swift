import AppKit
import SoapcapCore
import SwiftUI

/// What the app leaves on a Mac, and removing it. A model that soapcap or
/// Ollama installed is not the app's and is never touched.
struct Uninstaller {
    var bundleID = Bundle.main.bundleIdentifier ?? "local.soapcap.session"
    var library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
    var app = Bundle.main.bundleURL

    /// Every place the app, or macOS on its behalf, may have put something.
    var places: [URL] {
        [library.appending(path: "Application Support/Soapcap"),         // the models it downloaded
         library.appending(path: "Caches/\(bundleID)"),
         library.appending(path: "HTTPStorages/\(bundleID)"),
         library.appending(path: "Saved Application State/\(bundleID).savedState")]
    }

    /// Those of them that are there.
    var leftovers: [URL] { places.filter { FileManager.default.fileExists(atPath: $0.path) } }

    /// How much disk the leftovers take.
    var bytes: Int64 {
        leftovers.reduce(0) { total, place in
            let files = FileManager.default.enumerator(at: place, includingPropertiesForKeys: [.fileSizeKey])
            return total + (files?.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
                .reduce(0) { $0 + Int64($1) } ?? 0)
        }
    }

    var summary: String {
        "This removes the models Soapcap downloaded (\(ByteCount.text(bytes))), its settings, and its Microphone and Screen Recording permissions, then moves Soapcap to the Trash.\n\nA Bonsai or an Ollama that something else installed is left alone."
    }

    /// Deletes the leftovers, and returns any that would not go.
    @discardableResult
    func removeData() -> [URL] {
        leftovers.filter { (try? FileManager.default.removeItem(at: $0)) == nil }
    }

    /// Drops the app's settings and has macOS forget its permissions.
    func forget() {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "All", bundleID]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        if (try? reset.run()) != nil { reset.waitUntilExit() }
    }
}

/// The app-menu item that removes the app and everything it put on the Mac.
struct UninstallCommand: View {
    /// Ends a draft and frees the note model first.
    let stop: () async -> Void

    var body: some View { Button("Uninstall Soapcap…") { ask() } }

    @MainActor private func ask(_ uninstaller: Uninstaller = Uninstaller()) {
        let question = NSAlert()
        question.alertStyle = .warning
        question.messageText = "Uninstall Soapcap?"
        question.informativeText = uninstaller.summary
        question.addButton(withTitle: "Cancel")                 // the first button is what Return chooses
        question.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        guard question.runModal() == .alertSecondButtonReturn else { return }
        Task { @MainActor in
            await stop()
            uninstaller.removeData()
            uninstaller.forget()
            NSWorkspace.shared.recycle([uninstaller.app]) { _, error in
                DispatchQueue.main.async {
                    if error != nil {
                        // An app opened straight from a download runs from a place it can't be binned from.
                        let last = NSAlert()
                        last.messageText = "One step left"
                        last.informativeText = "Everything Soapcap downloaded is gone. Drag Soapcap itself to the Trash to finish."
                        last.runModal()
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
