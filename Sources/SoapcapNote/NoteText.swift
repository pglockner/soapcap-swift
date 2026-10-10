import Foundation

/// Reading a drafted note line by line, tolerant of what a model does to it.
enum NoteText {
    static let allSections = ["SUBJECTIVE", "OBJECTIVE", "ASSESSMENT", "PLAN", "DATA", "BEHAVIOR", "INTERVENTION", "RESPONSE"]
    static let notAddressed = "notaddressedinthissession"

    static func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    /// Joins lines and drops trailing blank ones.
    static func join(_ lines: [String]) -> String {
        var lines = lines
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Is this line the `name` section's header, whatever markup surrounds it
    /// ("**OBJECTIVE:**", text after the colon)?
    static func isHeader(_ line: String, _ name: String) -> Bool {
        line.matches("^[#* \\t]*\(name)[* \\t]*:")
    }

    /// The text after a header line's colon.
    static func afterHeader(_ line: String) -> String {
        line.firstIndex(of: ":").map { String(line[line.index(after: $0)...]) } ?? line
    }

    /// Is a section's text empty, or just "Not addressed in this session"?
    static func isHollow(_ body: String) -> Bool {
        let bare = body.filter { !" \t*.".contains($0) }
        return bare.isEmpty || bare.lowercased() == notAddressed
    }
}

extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    func replacing(pattern: String, with replacement: String) -> String {
        replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
