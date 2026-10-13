import Foundation

/// A pause in a session: where in the session it fell, and how long it lasted.
struct SessionPause: Hashable {
    /// The session's clock when Pause was pressed, in seconds. The clock
    /// stands still through a pause, so this is the time on both sides of it.
    let at: Int
    /// How long the pause lasted by the clock on the wall, in seconds. The
    /// session's own clock doesn't count it.
    var length = 0

    /// "1 minute, 35 seconds"; nil for a pause that was over at once.
    var lasted: String? {
        length < 1 ? nil : Duration.seconds(length).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// The line the transcript shows where the pause fell.
    var text: String { lasted.map { "Paused for \($0)" } ?? "Paused" }

    /// The same with the moment it began, for the mark on the ruler.
    var textWithTime: String { "Paused at \(SessionClock.text(at))" + (lasted.map { " for \($0)" } ?? "") }
}
