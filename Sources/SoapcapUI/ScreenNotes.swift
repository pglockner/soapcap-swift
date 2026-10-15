/// What stands under the transcript and under the note: notices about what
/// was done to it, and a warning when de-identifying it failed. Each keeps
/// its own while the other is on screen, since the transcript can be gone
/// back to once there is a note.
struct ScreenNotes {
    /// Those of the one on screen.
    var notice = ""
    var warning = ""
    private var showing: SessionModel.Stage = .transcript
    private var kept: [SessionModel.Stage: (notice: String, warning: String)] = [:]

    /// Swaps in those of the transcript or the note.
    mutating func put(_ step: SessionModel.Stage) {
        guard step != showing else { return }
        kept[showing] = (notice, warning)
        (notice, warning) = kept[step] ?? ("", "")
        showing = step
    }

    /// Adds a line to the notices on screen.
    mutating func tell(_ line: String) {
        notice = [notice, line].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
