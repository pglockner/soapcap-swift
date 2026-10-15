// Drafts a note from a transcript file and prints it. A development aid for
// checking drafting without the window:
//   swift run NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]
// FILE can be `sample`, for the sample session that ships with the app.
// MODEL is `bonsai`, a model's name as Settings shows it (run as the app
// would: by Ollama if Ollama has it, or else the default model from the
// app's own file), or `gguf:PATH` to run a model file with the app's engine
// and the prompts in the order Ollama gets them.
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
let model = args.dropFirst(2).first ?? "llama3.1:8b"
let backend: any NoteBackend
if model.hasPrefix("gguf:") {
    let weights = URL(fileURLWithPath: String(model.dropFirst(5)))
    backend = EngineBackend(install: .init(server: NoteModel.bonsai.install.server, weights: weights),
                            label: "llama-server", resumesFromSharedOpening: false)
} else {
    backend = await ModelCatalog.backend(for: model)
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
