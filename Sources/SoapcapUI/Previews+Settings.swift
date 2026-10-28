import SoapcapCore
import SoapcapNote
import SwiftUI

// The Settings window: model downloads, the model test, and its foot.

/// A download for each note model, on paths where nothing is installed:
/// the default model on this Mac, and Bonsai in a given state.
@MainActor private func downloads(bonsai state: ModelDownload.State) -> [ModelDownload] {
    NoteModel.all.map { model in
        let download = ModelDownload(file: model.weights, target: URL(fileURLWithPath: "/nonexistent/soapcap-preview/\(model.weights.name)"))
        download.show(model == .bonsai ? state : model.id == ModelCatalog.defaultModel ? .ready : .missing)
        return download
    }
}

#Preview("Settings, Bonsai to download") { SettingsView(test: SessionModel().modelTest, downloads: downloads(bonsai: .missing)) }

#Preview("Settings, Bonsai downloading") {
    SettingsView(test: SessionModel().modelTest, downloads: downloads(bonsai: .working(FetchProgress(bytes: 2_100_000_000, total: 5_946_648_928, bytesPerSecond: 24_000_000))))
}

#Preview("Settings, Bonsai installed") { SettingsView(test: SessionModel().modelTest, downloads: downloads(bonsai: .ready)) }

#Preview("Settings, model missing") { SettingsView(test: SessionModel().modelTest, setup: ModelSetup(isReady: false)) }

#Preview("Settings, downloading") {
    SettingsView(test: SessionModel().modelTest, setup: { let s = ModelSetup(isReady: false); s.show(.working(file: "weights.safetensors", fraction: 0.43)); return s }())
}

#Preview("Settings, model tested good") { SettingsView(test: testedModel(.good(model: "gemma4-e4b", seconds: 48))) }

#Preview("Settings, model being tested") { SettingsView(test: testedModel(.running("Drafting a SOAP note with Gemma 4 E4B…"), note: nil)) }

#Preview("Settings, the end") { SettingsView(test: SessionModel().modelTest).defaultScrollAnchor(.bottom) }
