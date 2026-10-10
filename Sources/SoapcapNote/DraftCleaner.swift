import Foundation

/// Safety nets against known ways a model's prose draft goes wrong.
public enum DraftCleaner {
    static let fallback = "No observable presentation details available from a text-only transcript."
    static let planOfCare = "The current plan of care will continue."

    /// Every net, in order; the Plan default applies to SOAP only.
    public static func clean(_ draft: String, format: NoteFormat) -> String {
        let cleaned = strippingTrailingDisclaimer(strippingContaminatedFallback(strippingTranscriptEcho(draft)))
        return format == .soap ? defaultingPlan(cleaned) : cleaned
    }

    /// Small models sometimes echo the transcript back after the note. The
    /// prompt introduces it with a "TRANSCRIPT:" line, so cut there rather
    /// than duplicate PHI into the output.
    static func strippingTranscriptEcho(_ note: String) -> String {
        NoteText.join(Array(NoteText.lines(note).prefix { !$0.matches("^TRANSCRIPT:\\s*$") }))
    }

    /// The Objective fallback sentence is meant to stand alone. A model
    /// sometimes appends it to a line that has a real observation, which
    /// then contradicts itself; drop the fallback from such a line.
    static func strippingContaminatedFallback(_ note: String) -> String {
        NoteText.join(NoteText.lines(note).map { line in
            guard line != fallback, let found = line.range(of: fallback) else { return line }
            return String(line[..<found.lowerBound]).replacing(pattern: "[ \\t]+$", with: "")
        })
    }

    /// Drops one trailing paragraph that opens like an aside about the
    /// transcript ("Note: this appears to be a test recording…"). Real Plan
    /// content essentially never opens a paragraph that way.
    static func strippingTrailingDisclaimer(_ note: String) -> String {
        var lines = NoteText.lines(note)
        while lines.last == "" { lines.removeLast() }
        guard let blank = lines.lastIndex(of: ""), blank + 1 < lines.count else { return NoteText.join(lines) }
        let first = lines[blank + 1].lowercased()
        let aside = first.matches("^(note|disclaimer|caveat|n\\.b\\.)[ \\t]*[:,-]") || first.matches("^please note[ \\t]*[:,-]")
        return NoteText.join(aside ? Array(lines[..<blank]) : lines)
    }

    /// The SOAP prompt says Plan always states the plan of care, but a model
    /// can still leave it empty or "Not addressed". Either becomes the
    /// plan-of-care sentence. Plan is the last section, so it runs to the end.
    static func defaultingPlan(_ note: String) -> String {
        let lines = NoteText.lines(note)
        guard let plan = lines.lastIndex(where: { NoteText.isHeader($0, "PLAN") }),
              NoteText.isHollow(lines[(plan + 1)...].joined()) else { return NoteText.join(lines) }
        return NoteText.join(lines[...plan] + [planOfCare])
    }
}
