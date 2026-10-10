import SoapcapCapture
import SoapcapCore
import SwiftUI

@MainActor private func sampleScreen(_ set: (SessionModel) -> Void) -> some View {
    let m = SessionModel()
    set(m)
    return ContentView().environmentObject(m).frame(width: 560, height: 420)
}

private let previewLines = [
    LiveLine(speaker: "Therapist", text: "How has your sleep been since we last spoke?", isFinal: true),
    LiveLine(speaker: "Client", text: "Better, mostly. The breathing exercises helped the first few nights.", isFinal: true),
    LiveLine(speaker: "Therapist", text: "That's good to hear.", isFinal: true),
    LiveLine(speaker: "Client", text: "Then on Thursday I had the argument with my", isFinal: false),
]

#Preview("Ready") { sampleScreen { _ in } }

#Preview("Recording") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Paused") {
    sampleScreen { $0.phase = .paused; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Transcript") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.notice = "transcript: redacted 2 span(s): FIRST_NAME x1, DATE x1"
    }
}

#Preview("Transcript, not de-identified") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.warning = "Not de-identified. This transcript still contains names and other identifying details.\nThe model's files could not be read."
    }
}

#Preview("Checks, all ready") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .ok, "Soapcap can hear your side."),
            Check("Call audio", .ok, "Soapcap can hear what the Mac is playing."),
            Check("Speech recognition", .ok, "Ready for en-US, on this Mac only."),
            Check("Note model", .ok, "llama3.1:8b is ready to draft notes."),
            Check("De-identify", .ok, "The model is installed."),
        ])
    }
}

#Preview("Checks, problems") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .warning, "Not asked yet. macOS will ask the first time you start recording."),
            Check("Call audio", .failed,
                  "Turn on Soapcap under Screen & System Audio Recording, then quit and reopen Soapcap. If it is already on, remove it from the list and add it again.",
                  fix: .init(label: "Open Screen Recording settings", url: URL(string: "x-apple.systempreferences:")!)),
            Check("Speech recognition", .ok, "Ready for en-US, on this Mac only."),
            Check("Note model", .failed, "The model 'llama3.1:8b' is not pulled. Run: ollama pull llama3.1:8b\nOr choose another model in Settings."),
            Check("De-identify", .warning, "Optional and not set up. Open Settings (Cmd-comma) to get the model."),
        ])
    }
}

#Preview("Drafting") {
    sampleScreen { $0.phase = .working("Drafting a soap note with llama3.1:8b…  412 tokens") }
}

#Preview("Note") {
    sampleScreen {
        $0.phase = .note
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better since starting the breathing exercises.\n\nOBJECTIVE:\nOn time via video. Engaged. Affect congruent; mood stressed. Speech clear. Thought process linear. Insight good; judgment intact. No psychomotor abnormalities. No SI/HI reported.\n\nASSESSMENT:\nSleep is improving; conflict at home remains a stressor.\n\nPLAN:\nContinue the breathing exercises nightly. Return next week."
        $0.notice = "qwen3:14b hasn't been tested with soapcap's prompts — proofread it with extra care."
    }
}

#Preview("Settings, model missing") { SettingsView(setup: ModelSetup(isReady: false)) }

#Preview("Settings, downloading") {
    SettingsView(setup: { let s = ModelSetup(isReady: false); s.show(.working(file: "weights.safetensors", fraction: 0.43)); return s }())
}
