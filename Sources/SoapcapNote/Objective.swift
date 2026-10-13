import Foundation

/// SOAP's Objective section: a fixed mental-status frame filled in from the
/// model's short phrases, never free prose.
public enum Objective {
    /// What the Objective pass produced.
    public enum Result: Equatable, Sendable {
        /// The transcript had no client lines to assess.
        case noClient
        /// The pass failed or returned something unusable.
        case failed
        case assessed(Findings)
    }

    public struct Findings: Equatable, Sendable, Decodable {
        public var mentalStatus: [String: String]
        public var riskStatus: String
        public var riskKind: String

        public init(mentalStatus: [String: String], riskStatus: String = "", riskKind: String = "") {
            self.mentalStatus = mentalStatus
            self.riskStatus = riskStatus
            self.riskKind = riskKind
        }

        private enum Key: String, CodingKey { case mental_status, risk, risk_kind }
        private enum RiskKey: String, CodingKey { case status }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            mentalStatus = try c.decode([String: String?].self, forKey: .mental_status).compactMapValues { $0 }
            let risk = try? c.nestedContainer(keyedBy: RiskKey.self, forKey: .risk)
            riskStatus = (try? risk?.decodeIfPresent(String.self, forKey: .status)) ?? ""
            riskKind = (try? c.decodeIfPresent(String.self, forKey: .risk_kind)) ?? ""
        }
    }

    /// Reads the model's JSON reply; anything that doesn't fit is `.failed`.
    public static func result(fromJSON json: String) -> Result {
        (try? JSONDecoder().decode(Findings.self, from: Data(json.utf8))).map(Result.assessed) ?? .failed
    }

    // MARK: rendering

    /// The Objective's body. `note` is the rest of the note: its own risk
    /// language is a second check before "No SI/HI reported." is written, so
    /// one missed disclosure in one pass is not enough to print it.
    public static func render(_ result: Result, note: String) -> String {
        switch result {
        case .noClient:
            return "On time via video. [No client speech was captured; complete the Objective manually.] " + notAssessed
        case .failed:
            return "On time via video. [Objective could not be drafted; complete manually.] " + notAssessed
        case .assessed(let found):
            let m = { (key: String) in slot(found.mentalStatus[key]) }
            return "On time via video. \(capitalized(m("engagement"))). "
                + "Affect \(lowered(m("affect"))); mood \(lowered(m("mood"))). "
                + "Speech \(lowered(m("speech"))). "
                + "Thought process \(lowered(m("thought_process"))). "
                + "Insight \(lowered(m("insight"))); judgment \(lowered(m("judgment"))). "
                + "\(capitalized(m("psychomotor"))). "
                + risk(found, note: note)
        }
    }

    static let notAssessed = "[SI/HI status not assessed; confirm before signing.]"

    /// A disclosure is named by kind only, from a fixed list: a small model's
    /// own summary called an active plan "passive, no plan or intent" in
    /// testing. The details are in Assessment and Plan.
    static func risk(_ found: Findings, note: String) -> String {
        if found.riskStatus == "disclosed" {
            let kinds = ["SI": "SI", "HI": "HI", "SI and HI": "SI and HI", "self-harm": "Self-harm"]
            return (kinds[found.riskKind] ?? "Safety risk") + " reported; see Assessment and Plan."
        }
        if mentionsRisk(note) { return "[The note mentions a safety concern; confirm SI/HI status before signing.]" }
        return "No SI/HI reported."
    }

    static func slot(_ phrase: String?) -> String {
        guard let phrase, !phrase.allSatisfy(\.isWhitespace) else { return "[not assessed]" }
        return phrase.replacing(pattern: "^\\s+", with: "").replacing(pattern: "[\\s.;,]+$", with: "")
    }

    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Mid-sentence slots start lowercase ("Affect constricted"), unless the word is an acronym.
    static func lowered(_ s: String) -> String {
        s.matches("^[A-Z][a-z]") ? s.prefix(1).lowercased() + s.dropFirst() : s
    }

    // MARK: risk language

    /// Lowercase, straighten curly quotes, drop punctuation, collapse space.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacing(pattern: "[‘’]", with: "'").replacing(pattern: "[“”]", with: "\"")
            .replacing(pattern: "[^a-z0-9 \\n]", with: "").replacing(pattern: "\\s+", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    /// Words that suggest a safety risk was documented. Matched against
    /// normalized text, so "self-harm" arrives as "selfharm".
    static let riskPattern = "suicid|homicid|self harm|selfharm|harm (themself|themselves|himself|herself|others|someone)|better off|safety plan|988|crisis"

    /// Does the note use risk language, other than plain denials ("denied
    /// suicidal ideation", "no indication of self-harm or suicidal
    /// ideation")? The gap between a denial and the risk term can't cross
    /// "but"/"however"/…, so "denied a plan but reported passive suicidal
    /// ideation" still counts.
    static func mentionsRisk(_ note: String) -> Bool {
        let term = "(suicid[a-z]*|homicid[a-z]*|selfharm|self harm)( ideation| thoughts| behaviou?rs?)?"
        let gap = "(?:(?!\\b(but|though|although|however|yet|except)\\b)[a-z ]){0,40}?"
        let denial = "\\b(denied|denies|denying|no|not|without)\\b" + gap + term + "(( or| and| nor)" + gap + term + ")*"
        return normalized(note).replacing(pattern: denial, with: "").matches(riskPattern)
    }

    // MARK: splicing

    /// `note` with its OBJECTIVE section's body replaced by `body`. Copes with
    /// extra header markup, text on the header line, a second OBJECTIVE, or
    /// none at all (inserted before ASSESSMENT, else PLAN, else at the end).
    public static func splice(_ body: String, into note: String) -> String {
        NoteText.setting("OBJECTIVE", to: body, in: note)
    }
}
