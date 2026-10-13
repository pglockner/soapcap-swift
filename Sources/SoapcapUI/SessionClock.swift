import SwiftUI

/// What a session is doing, and how long it has run: the time on a line of
/// its own, large enough to read from across a desk.
struct SessionClock: View {
    let title: String
    let symbol: String
    let tint: Color
    /// Seconds transcribed so far.
    let elapsed: Int
    /// Whether the symbol moves, as it does while the app is listening.
    var isLive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
                    .symbolEffect(.breathe, isActive: isLive && !reduceMotion)
            }
            .font(.title3)
            Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                .font(.system(size: 56, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}
