import SoapcapCore
import SoapcapNote
import SwiftUI

// The Settings window: model downloads, the model test, and its foot.

/// A Bonsai download in a given state, on a path where nothing is installed.
@MainActor private func bonsaiDownload(_ state: ModelDownload.State) -> ModelDownload {
    let nowhere = URL(fileURLWithPath: "/nonexistent/soapcap-preview/bonsai.gguf")
    let download = ModelDownload(file: BonsaiBackend.Install.weights, target: nowhere)
    download.show(state)
    return download
}

#Preview("Settings, Bonsai to download") { SettingsView(test: SessionModel().modelTest, bonsai: bonsaiDownload(.missing)) }

#Preview("Settings, Bonsai downloading") {
    SettingsView(test: SessionModel().modelTest, bonsai: bonsaiDownload(.working(FetchProgress(bytes: 2_100_000_000, total: 5_946_648_928, bytesPerSecond: 24_000_000))))
}

#Preview("Settings, Bonsai installed") { SettingsView(test: SessionModel().modelTest, bonsai: bonsaiDownload(.ready)) }

#Preview("Settings, model missing") { SettingsView(test: SessionModel().modelTest, setup: ModelSetup(isReady: false)) }

#Preview("Settings, downloading") {
    SettingsView(test: SessionModel().modelTest, setup: { let s = ModelSetup(isReady: false); s.show(.working(file: "weights.safetensors", fraction: 0.43)); return s }())
}

#Preview("Settings, model tested good") { SettingsView(test: testedModel(.good(model: "llama3.1:8b", seconds: 48))) }

#Preview("Settings, model being tested") { SettingsView(test: testedModel(.running("Drafting a SOAP note with llama3.1:8b…"), note: nil)) }

#Preview("Settings, the end") { SettingsView(test: SessionModel().modelTest).defaultScrollAnchor(.bottom) }
