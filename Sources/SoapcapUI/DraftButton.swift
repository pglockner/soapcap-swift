import SoapcapNote
import SwiftUI

/// Drafts with the chosen note model. When both models are installed it
/// says which, and the arrow beside it drafts with either: the two write
/// quite differently, and a therapist may want the other one's try. The
/// one drafted with becomes the chosen model, as if picked in Settings.
struct DraftButton: View {
    /// What it does, as "Draft note" or "Regenerate".
    let title: String
    let model: String
    /// Whether Return presses it.
    var isDefault = false
    let draft: (String) -> Void
    @ObservedObject private var bonsai = ModelDownload.bonsai
    @ObservedObject private var llama = ModelDownload.llama
    @State private var models: [String] = []

    var body: some View {
        Group {
            if models.count > 1 {
                // macOS draws this grey even when Return presses it.
                Menu(Self.title(title, with: model)) {
                    ForEach(models, id: \.self) { choice in
                        Button(Self.title(title, with: choice)) { draft(choice) }
                    }
                } primaryAction: {
                    draft(model)
                }
                .fixedSize()
            } else {
                Button(title) { draft(model) }
            }
        }
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        // Asked again when a model arrives or goes in Settings.
        .task(id: "\(bonsai.isInstalled) \(llama.isInstalled)") {
            models = await ModelCatalog.installed(host: SessionSettings().ollamaHost)
        }
    }

    static func title(_ title: String, with model: String) -> String {
        "\(title) with \(ModelCatalog.displayName(of: model))"
    }
}
