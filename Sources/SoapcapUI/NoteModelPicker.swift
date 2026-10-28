import SoapcapNote
import SwiftUI

/// Which note model drafts, beside Draft note and Regenerate: the models
/// write quite differently, and a therapist may want another one's try. It
/// is the same choice as Settings' Draft with, and shows only when more
/// than one model is installed.
struct NoteModelPicker: View {
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
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
                // Something for the update below to run on: an empty view
                // never appears, so the models would never be asked for.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        // Asked again when a model arrives or goes in Settings.
        .onReceive(ModelDownload.changes) { models = ModelCatalog.installed() }
    }
}
