import Foundation

public struct DraftedNote: Equatable, Sendable {
    public var text: String
    /// Things to tell the clinician about this note; never part of it.
    public var warnings: [String]
}

/// What the drafter is doing right now, for a status line.
public struct DraftProgress: Equatable, Sendable {
    public var title: String
    /// Tokens generated so far in the current pass, when the backend streams.
    public var tokens: Int?
}

/// Drafts a note from a transcript with a local model: a prose draft, drafted
/// again while a section is missing, then for SOAP a separate Objective pass.
public struct NoteDrafter: Sendable {
    public var backend: any NoteBackend
    /// Drafts before settling for a note with a section missing or empty.
    public var attempts = 3
    /// The call side's speaker label; with no such lines there is no client to assess.
    public var systemLabel = "Client"
    public var sessionType = "telehealth"

    public init(backend: any NoteBackend) { self.backend = backend }

    /// The model is left loaded afterwards so another draft starts at once;
    /// call `backend.stop()` when the session is over. `minutes` is the
    /// session's length, for the note's first line.
    public func draft(format: NoteFormat, transcript: String, minutes: Int? = nil,
                      progress: @escaping @Sendable (DraftProgress) -> Void = { _ in }) async throws -> DraftedNote {
        var warnings = backend.cautions
        let label = backend.label
        let prompt = try Prompts.draft(format, transcript: transcript)
        // Past the cap a model silently loses part of its input, and what it
        // writes then can look fine while missing whole sections.
        if ContextSize.exceedsCap(prompt, headroom: 2048) {
            warnings.append("This transcript is very long — it may be more than \(label) can take in at once, so sections of the note may be missing or wrong. Check the note against the transcript.")
        }

        let hasClient = transcript.split(separator: "\n").contains { $0.hasPrefix("\(systemLabel): ") }
        var objectivePrompt: String?
        var objective = Objective.Result.failed
        if format == .soap {
            if hasClient {
                objectivePrompt = try Prompts.objective(transcript: transcript)
            } else {
                // The model would rate the therapist instead.
                objective = .noClient
                warnings.append("No \(systemLabel) lines in the transcript — the Objective is left for you to complete.")
            }
        }

        // One context size for every pass, the largest any needs: a backend
        // loads the model again when the size changes between requests.
        let context = max(ContextSize.estimate(prompt, headroom: 2048),
                          objectivePrompt.map { ContextSize.estimate($0, headroom: 3072) } ?? 0)
        progress(DraftProgress(title: "Loading \(label)…"))
        try await backend.start(context: context)

        // A small model sometimes leaves a section out, or writes "Not
        // addressed in this session" under one the transcript plainly covers.
        // Another draft usually comes out whole. A transcript of a few lines
        // can't fill every section, so there only a missing section counts;
        // one with no client speech has nothing to fill them with, so it
        // gets the one draft.
        let lenient = transcript.split(whereSeparator: \.isWhitespace).count < 150
        let limit = hasClient ? max(attempts, 1) : 1
        var best: (note: String, faults: [String], cutOff: Bool)?
        var tries = 0
        while tries < limit {
            tries += 1
            let title = tries == 1 ? "Drafting a \(format.rawValue) note with \(label)…"
                : "Drafting the \(format.rawValue) note again with \(label) (\(tries) of \(limit))…"
            progress(DraftProgress(title: title))
            let reply: ModelReply
            do {
                reply = try await backend.request(prompt: prompt, cap: 2000, schema: nil) {
                    progress(DraftProgress(title: title, tokens: $0))
                }
            } catch {
                if best != nil { break }
                throw error
            }
            let note = DraftCleaner.clean(reply.text, format: format)
            let faults = NoteFaults.faults(in: note, sections: format.draftSections, lenient: lenient)
            if best == nil || faults.count < best!.faults.count { best = (note, faults, reply.cutOff) }
            if faults.isEmpty { break }
        }
        guard let best, !best.note.isEmpty else { throw NoteError.emptyNote }
        if !best.faults.isEmpty, hasClient {
            warnings.append("The note is still incomplete after \(tries) draft\(tries == 1 ? "" : "s") (\(best.faults.joined(separator: "; "))) — check it against the transcript.")
        }
        if best.cutOff { warnings.append("\(label) hit its output limit — the end of the note may be cut off.") }

        var note = best.note
        if format == .soap {
            if let objectivePrompt {
                // A failed Objective pass never costs the rest of the note:
                // the Objective then says plainly that it needs completing.
                let title = "Drafting the Objective with \(label)…"
                progress(DraftProgress(title: title))
                if let found = await structured(prompt: objectivePrompt, title: title, progress: progress) {
                    objective = found
                } else {
                    warnings.append("The Objective pass failed — complete the Objective by hand.")
                }
            }
            note = Objective.splice(Objective.render(objective, note: note), into: note)
        }
        return DraftedNote(text: SessionLine.adding(minutes: minutes, type: sessionType, to: note), warnings: warnings)
    }

    /// The Objective request. The schema is enforced by the server, but a
    /// reply can still be cut off or malformed, so one bad reply is retried
    /// once. The low cap stops a field that runs on from costing minutes.
    private func structured(prompt: String, title: String,
                            progress: @escaping @Sendable (DraftProgress) -> Void) async -> Objective.Result? {
        guard let schema = try? Prompts.objectiveSchema() else { return nil }
        for _ in 1...2 {
            guard let reply = try? await backend.request(prompt: prompt, cap: 600, schema: schema, tokens: {
                progress(DraftProgress(title: title, tokens: $0))
            }) else { return nil }
            if !reply.cutOff, Self.hasEveryField(reply.text),
               case .assessed(let found) = Objective.result(fromJSON: reply.text) {
                return .assessed(found)
            }
        }
        return nil
    }

    static func hasEveryField(_ json: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return false }
        return Prompts.objectiveFields.allSatisfy { object[$0] != nil }
    }
}
