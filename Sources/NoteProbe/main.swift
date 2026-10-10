// Drafts a note from a transcript file and prints it. A development aid for
// checking drafting without the window:
//   swift run NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]
import Foundation
import SoapcapNote

func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, let transcript = try? String(contentsOfFile: path, encoding: .utf8) else {
    say("usage: NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]")
    exit(2)
}
let format = args.dropFirst().first.flatMap(NoteFormat.init) ?? .soap
let model = args.dropFirst(2).first ?? "llama3.1:8b"
let backend = OllamaBackend(model: model)
let drafter = NoteDrafter(backend: backend)

final class Title: @unchecked Sendable { var last = "" }
let title = Title()
do {
    let started = Date()
    let note = try await drafter.draft(format: format, transcript: transcript.trimmingCharacters(in: .newlines),
                                       minutes: args.dropFirst(3).first.flatMap { Int($0) }) { progress in
        if progress.title != title.last { title.last = progress.title; say(progress.title) }
    }
    await backend.stop()
    say("done in \(Int(Date().timeIntervalSince(started)))s")
    for warning in note.warnings { say("warning: \(warning)") }
    print(note.text)
} catch {
    await backend.stop()
    say("failed: \(error.localizedDescription)")
    exit(1)
}
