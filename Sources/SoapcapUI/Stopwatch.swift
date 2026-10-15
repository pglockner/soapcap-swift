import Foundation

/// The session's clock. It runs while the session is heard and stands still
/// while it is paused, and it knows how long the pause in hand has lasted.
/// It is told the time, so tests can set it.
struct Stopwatch {
    /// Seconds run before the stretch in hand.
    private var before: TimeInterval = 0
    /// When the stretch in hand began; nil while the clock stands still.
    private var since: Date?
    /// When the pause in hand began.
    private var pausedSince: Date?

    /// Seconds run so far, at `now`.
    func seconds(at now: Date) -> Int {
        Int(before + (since.map { now.timeIntervalSince($0) } ?? 0))
    }

    mutating func run(at now: Date) { since = now }

    /// Stops the clock, and gives the seconds run.
    @discardableResult
    mutating func halt(at now: Date) -> Int {
        if let since { before += now.timeIntervalSince(since) }
        since = nil
        return Int(before)
    }

    /// Stops the clock for a pause, and gives the seconds run.
    mutating func pause(at now: Date) -> Int {
        pausedSince = now
        return halt(at: now)
    }

    /// How long the pause in hand lasted, as it ends; nil if none was.
    mutating func endPause(at now: Date) -> Int? {
        guard let pausedSince else { return nil }
        self.pausedSince = nil
        return Int(now.timeIntervalSince(pausedSince))
    }
}
