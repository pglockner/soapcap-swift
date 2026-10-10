import Foundation

public enum NoteFaults {
    /// What is wrong with a draft, one fault per entry, empty if it is sound:
    /// a wanted section with no header, or one that is empty or just "Not
    /// addressed in this session". With `lenient` only a missing header
    /// counts, for a transcript too short to fill every section.
    public static func faults(in note: String, sections: [String], lenient: Bool = false) -> [String] {
        var current: String?
        var seen: Set<String> = []
        var body: [String: String] = [:]
        for var line in NoteText.lines(note) {
            for name in NoteText.allSections where NoteText.isHeader(line, name) {
                current = name
                seen.insert(name)
                line = NoteText.afterHeader(line)
            }
            if let current { body[current, default: ""] += line }
        }
        return sections.compactMap { name in
            if !seen.contains(name) { return "no \(name) section" }
            if !lenient, NoteText.isHollow(body[name] ?? "") { return "\(name) is empty or \"Not addressed\"" }
            return nil
        }
    }
}
