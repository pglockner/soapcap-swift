// Drafts a note from a transcript file and prints it. A development aid for
// checking drafting without the window:
//   swift run NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]
// FILE can be `sample`, for the sample session that ships with the app.
// MODEL is a note model's name as Settings stores it (`gemma4-e4b`, the
// default, `qwen3.5-9b` or `bonsai`), run as the app would from its own
// file, or `gguf:PATH` to run any model file with the app's engine, each
// pass reading the whole transcript.
import Foundation
import SoapcapNote

func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let args = Array(CommandLine.arguments.dropFirst())
let isSample = args.first == "sample"
guard let path = args.first, let transcript = isSample ? try? SampleSession.transcript() : try? String(contentsOfFile: path, encoding: .utf8) else {
    say("usage: NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]")
    exit(2)
}
let format = args.dropFirst().first.flatMap(NoteFormat.init) ?? .soap
let model = args.dropFirst(2).first ?? ModelCatalog.defaultModel
let backend: any NoteBackend
if model.hasPrefix("gguf:") {
    let weights = URL(fileURLWithPath: String(model.dropFirst(5)))
    backend = EngineBackend(install: .init(server: NoteModel.bonsai.install.server, weights: weights),
                            label: "llama-server", resumesFromSharedOpening: false)
} else if NoteModel.named(model) != nil {
    backend = ModelCatalog.backend(for: model)
} else {
    say("unknown model \(model): use \(NoteModel.all.map(\.id).joined(separator: ", ")) or gguf:PATH")
    exit(2)
}
let drafter = NoteDrafter(backend: backend)

final class Title: @unchecked Sendable { var last = "" }
let title = Title()
do {
    let started = Date()
    let note = try await drafter.draft(format: format, transcript: transcript.trimmingCharacters(in: .newlines),
                                       minutes: args.dropFirst(3).first.flatMap { Int($0) } ?? (isSample ? SampleSession.minutes : nil)) { progress in
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
