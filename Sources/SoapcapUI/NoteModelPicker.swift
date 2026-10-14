import SoapcapNote
import SwiftUI

/// Which note model drafts, beside Draft note and Regenerate: the two write
/// quite differently, and a therapist may want the other one's try. It is
/// the same choice as Settings' Draft with, and shows only when both models
/// are installed.
struct NoteModelPicker: View {
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
    @ObservedObject private var bonsai = ModelDownload.bonsai
    @ObservedObject private var llama = ModelDownload.llama
    @State private var models: [String] = []

    var body: some View {
        Group {
            if models.count > 1 {
                Picker("Note model", selection: Binding(get: { SessionSettings.noteModel(stored: noteModel) }, set: { noteModel = $0 })) {
                    ForEach(models, id: \.self) { Text(ModelCatalog.displayName(of: $0)).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("The model that drafts the note")
            } else {
                // Something for the task below to run on: an empty view
                // never appears, so the models would never be asked for.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        // Asked again when a model arrives or goes in Settings.
        .task(id: "\(bonsai.isInstalled) \(llama.isInstalled)") {
            models = await ModelCatalog.installed(host: SessionSettings().ollamaHost)
        }
    }
}
