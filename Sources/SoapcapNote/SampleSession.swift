import Foundation

/// A fictional session to try a note model on: soapcap's
/// `03-selfreport-diagnosis-9min`, unchanged. Nine minutes in which a client
/// describes episodes of chest tightness and anxiety, practises a breathing
/// exercise, and agrees a sleep routine and a possible referral. Long enough
/// that every section of a note has something to say.
public enum SampleSession {
    public static let minutes = 9
    /// The speaker label of the call side in the sample's lines.
    public static let systemLabel = "Client"

    /// Beside the prompts: in the built app in Contents/Resources/samples,
    /// under `swift build` and `swift test` in the package's resource bundle.
    static let file: URL = {
        let name = "samples/03-selfreport-diagnosis-9min.txt"
        if let inApp = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: inApp.path) {
            return inApp
        }
        return Bundle.module.resourceURL!.appendingPathComponent(name)
    }()

    public static func transcript() throws -> String {
        try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines)
    }

    /// What is wrong with a note drafted from the sample, empty if the model
    /// did its job: a section missing or empty, or anything the drafter had
    /// to caution about. `cautions` are the model's standing ones (an
    /// untested model, say), which say nothing about this note.
    public static func problems(in note: DraftedNote, cautions: [String] = []) -> [String] {
        NoteFaults.faults(in: note.text, sections: ["SUBJECTIVE", "OBJECTIVE", "ASSESSMENT", "PLAN"])
            + note.warnings.filter { !cautions.contains($0) }
    }
}
