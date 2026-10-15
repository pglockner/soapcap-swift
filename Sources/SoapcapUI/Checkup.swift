import AppKit
import SoapcapCapture
import SoapcapCore
import SoapcapNote

/// Looking the Mac over for the checks screen, and doing what the screen's
/// buttons stand for outside the window. Where the result is shown is the
/// session's business.
struct Checkup {
    /// What the setup screen's buttons reach outside this window.
    struct Fixer {
        var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
        var askForMicrophone: () async -> Void = { await Readiness.askForMicrophone() }
        var askForCallAudio: () async -> Void = { await Readiness.askForCallAudio() }
    }

    let gather: () async -> [Check]
    let fixer: Fixer

    /// Everything the app looks at: its own permissions and speech
    /// recognition, the note model, de-identification, and memory.
    static func everything(settings: SessionSettings, memory: @escaping () -> MemoryStatus?) -> () async -> [Check] {
        {
            await Readiness.checks(locale: settings.locale)
                + [await ModelCatalog.check(settings.noteModel, host: settings.ollamaHost)] + [ModelSetup.check()]
                + [ModelCatalog.memoryCheck(memory(), model: settings.noteModel)]
        }
    }

    /// Does what a button stands for. macOS answers a permission question
    /// at once, so `recheck` follows one.
    @MainActor func perform(_ action: Check.Fix.Action, then recheck: @escaping @MainActor () -> Void) {
        switch action {
        case .open(let url):
            fixer.open(url)
        case .askForMicrophone:
            Task { await fixer.askForMicrophone(); recheck() }
        case .askForCallAudio:
            Task { await fixer.askForCallAudio(); recheck() }
        case .showSettings:
            break       // the window opens its own Settings
        }
    }
}
