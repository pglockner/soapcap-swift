import AppKit
import SoapcapCore
import SoapcapNote
import SwiftUI

/// What the app leaves on a Mac, and removing it.
struct Uninstaller {
    var bundleID = Bundle.main.bundleIdentifier ?? "com.jukenzie.soapcap"
    var library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
    var app = Bundle.main.bundleURL
    /// A cache macOS keeps for each user outside the Library. What it compiles
    /// for an app's drawing goes there, in a folder named for the app.
    var systemCache: URL? = {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &path, path.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }()

    /// Where macOS files what the app fetches. The app has no use for it, and
    /// versions before 0.8 let it hold a note model's requests and replies.
    var cache: URL { library.appending(path: "Caches/\(bundleID)") }

    /// The models it downloaded.
    var models: URL { library.appending(path: "Application Support/Soapcap") }

    /// Every place the app, or macOS on its behalf, may have put something.
    var places: [URL] {
        [models,
         cache,
         library.appending(path: "HTTPStorages/\(bundleID)"),
         library.appending(path: "Saved Application State/\(bundleID).savedState")]
            + [systemCache?.appending(path: bundleID)].compactMap { $0 }
    }

    /// Deletes the cache. Done whenever the app opens, so that nothing
    /// fetched in one run is still on disk in the next.
    func removeCache() { try? FileManager.default.removeItem(at: cache) }

    /// Settings an earlier version kept that this one no longer reads.
    static let retiredSettings = ["ollamaHost"]

    /// Deletes what an earlier version left and this one no longer uses:
    /// the file of a note model it no longer offers, and retired settings.
    /// Done whenever the app opens. The file of a model it does offer is
    /// kept, and so is a download of one still under way or stopped.
    func removeRetired(defaults: UserDefaults = .standard) {
        let noteModels = models.appending(path: "note-models")
        let kept = Set(NoteModel.all.flatMap { [$0.ownWeights, Fetcher.part(of: $0.ownWeights)].map(\.lastPathComponent) })
        let files = (try? FileManager.default.contentsOfDirectory(at: noteModels, includingPropertiesForKeys: nil)) ?? []
        for file in files where !kept.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
        for key in Self.retiredSettings { defaults.removeObject(forKey: key) }
    }

    /// Those of them that are there.
    var leftovers: [URL] { places.filter { FileManager.default.fileExists(atPath: $0.path) } }

    /// How much disk the models take.
    var bytes: Int64 {
        let files = FileManager.default.enumerator(at: models, includingPropertiesForKeys: [.fileSizeKey])
        return files?.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(0) { $0 + Int64($1) } ?? 0
    }

    var summary: String {
        "This removes the models Soapcap downloaded (\(ByteCount.text(bytes))), its settings, and its Microphone and System Audio Recording permissions, then moves Soapcap to the Trash."
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

/// The button in Settings that removes the app and everything it put on the Mac.
struct UninstallButton: View {
    /// Ends a draft and frees the note model first.
    let stop: () async -> Void

    var body: some View {
        Button { ask() } label: { Text("Uninstall Soapcap…").foregroundStyle(.red) }
    }

    @MainActor private func ask(_ uninstaller: Uninstaller = Uninstaller()) {
        let question = NSAlert()
        question.alertStyle = .warning
        question.messageText = "Uninstall Soapcap?"
        question.informativeText = uninstaller.summary
        // Beside a destructive button macOS gives Return to neither; Escape is Cancel's.
        question.addButton(withTitle: "Cancel")
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
                    // The draft is stopped already. A quit that waited for it again would
                    // wait for ever: nothing more on the main queue runs until this returns.
                    AppDelegate.beforeQuit = nil
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
