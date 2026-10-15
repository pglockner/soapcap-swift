import SwiftUI

/// While a session is heard, or paused: the clock, the buttons, and the
/// last few lines from each side.
struct TranscribingScreen: View {
    @EnvironmentObject var m: SessionModel
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if isPaused {
                SessionClock(title: "Paused", symbol: "pause.circle.fill", tint: .orange, elapsed: m.elapsed)
                Text("Nothing is being captured.").foregroundStyle(.secondary)
            } else {
                // Nothing is recorded: the app listens, and what it hears becomes text.
                SessionClock(title: "Transcribing", symbol: "microphone.fill", tint: .red, elapsed: m.elapsed, isLive: true)
            }
            HStack {
                if isPaused {
                    Button("Resume") { m.resume() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Pause") { m.pause() }
                }
                StopButton { m.stop() }
            }
            Spacer()
            LiveStrip(lines: m.liveLines).opacity(isPaused ? 0.5 : 1)
        }.frame(maxWidth: .infinity)
    }
}
