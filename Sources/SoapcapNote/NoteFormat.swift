import Foundation

public enum NoteFormat: String, CaseIterable, Sendable {
    case soap, dap, birp

    /// The sections the model's prose draft must fill. SOAP's Objective isn't
    /// one: it comes from a pass of its own (see `Objective`).
    public var draftSections: [String] {
        switch self {
        case .soap: ["SUBJECTIVE", "ASSESSMENT", "PLAN"]
        case .dap: ["DATA", "ASSESSMENT", "PLAN"]
        case .birp: ["BEHAVIOR", "INTERVENTION", "RESPONSE", "PLAN"]
        }
    }
}

/// The note's first line, e.g. "63 minutes, telehealth".
public enum SessionLine {
    public static func line(minutes: Int, type: String = "telehealth") -> String {
        switch minutes {
        case ...0: "under 1 minute, \(type)"
        case 1: "1 minute, \(type)"
        default: "\(minutes) minutes, \(type)"
        }
    }

    /// `note` under its session line, or unchanged when the length is unknown.
    public static func adding(minutes: Int?, type: String = "telehealth", to note: String) -> String {
        minutes.map { line(minutes: $0, type: type) + "\n\n" + note } ?? note
    }
}
