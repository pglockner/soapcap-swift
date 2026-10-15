import SwiftUI

/// Before a session: laid out as the session it leads to, with the clock
/// where it will run and what to see to first where the lines heard will
/// appear.
struct ReadyScreen: View {
    @EnvironmentObject var m: SessionModel

    var body: some View {
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
            VStack(spacing: 10) {
                Text("Use headphones, and turn on Do Not Disturb.").foregroundStyle(.secondary)
                if Beta.isBeta(AppVersion.current.marketing) {
                    HStack(spacing: 6) {
                        BetaBadge()
                        Text("Read every note before you use it.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: LiveStrip.height)
        }.frame(maxWidth: .infinity)
    }
}
