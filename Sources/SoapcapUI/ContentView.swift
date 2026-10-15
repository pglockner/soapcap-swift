import SwiftUI

/// The window: the screen for where the session has got to, under the bar.
struct ContentView: View {
    @EnvironmentObject var m: SessionModel
    /// Read here so that this window follows a change of model made in Settings.
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
    /// The version whose beta notice was last acknowledged.
    @AppStorage(SessionSettings.Key.betaNoticeSeen) private var betaNoticeSeen = ""

    /// The note model that drafts unless another is picked.
    private var chosenModel: String { SessionSettings.noteModel(stored: noteModel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // In place of the screen, not a sheet over it: macOS won't quit
            // an app while a sheet is up.
            if Beta.needsNotice(version: AppVersion.current.marketing, seen: betaNoticeSeen) {
                BetaNoticeView(version: AppVersion.current.marketing) { betaNoticeSeen = AppVersion.current.marketing }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch m.phase {
                case .idle: ReadyScreen()
                case .recording: TranscribingScreen(isPaused: false)
                case .paused: TranscribingScreen(isPaused: true)
                case .working(let msg):
                    WorkingView(message: msg, run: m.draftRun, test: m.modelTest, steps: m.draftSteps, tokens: m.draftTokens,
                                keepsEarlierNote: !m.note.isEmpty, stop: { m.stopDraft() })
                case .transcript: TranscriptScreen()
                case .note: NoteScreen()
                case .error(let msg): ErrorScreen(message: msg)
                case .checks(let checks):
                    ChecksView(checks: checks, test: m.modelTest, model: chosenModel,
                               perform: { m.perform($0) }, again: { m.diagnose() }, back: { m.back() })
                        // The line about the note model is about the one just chosen.
                        .onChange(of: noteModel) { m.diagnose() }
                }
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
}
