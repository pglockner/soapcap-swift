import SoapcapCore
import SwiftUI

// The checks screen, which is also the setup screen on a first run.

#Preview("Checks, all ready") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .ok, "Soapcap can hear your side."),
            Check("Call audio", .ok, "Soapcap can hear what the Mac is playing."),
            Check("Speech recognition", .ok, "Ready for en-US, on this Mac only."),
            Check("Note model", .ok, "llama3.1:8b is ready to draft notes."),
            Check("De-identify", .ok, "The model is installed."),
            Check("Memory", .ok, "16 GB, about 10 GB free now."),
        ])
    }
}

#Preview("Checks, problems") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .ok, "Soapcap can hear your side."),
            Check("Call audio", .ok, "Soapcap can hear what the Mac is playing."),
            Check("Speech recognition", .ok, "Ready for en-US, on this Mac only."),
            Check("Note model", .failed, "The model 'llama3.1:8b' is not pulled. Run: ollama pull llama3.1:8b\nOr choose another model in Settings.",
                  fix: .init(label: "Open Settings", action: .showSettings)),
            Check("De-identify", .warning, "Optional and not set up. The model is a 130 MB download in Settings.",
                  fix: .init(label: "Open Settings", action: .showSettings)),
        ])
    }
}

#Preview("Checks, first run") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .warning, "Needed to hear your side. macOS will ask whether Soapcap may use the microphone; choose Allow.",
                  fix: .init(label: "Allow the microphone", action: .askForMicrophone)),
            Check("Call audio", .warning,
                  "Needed to hear the other side. macOS will ask whether Soapcap may record your system audio; choose Allow. Only sound is heard, never the screen, and none of it is kept.",
                  fix: .init(label: "Allow call audio", action: .askForCallAudio)),
            Check("Speech recognition", .ok, "Ready for en-US, on this Mac only."),
            Check("Note model", .ok, "llama3.1:8b is ready to draft notes."),
            Check("De-identify", .warning, "Optional and not set up. The model is a 130 MB download in Settings.",
                  fix: .init(label: "Open Settings", action: .showSettings)),
        ])
    }
}

#Preview("Checks, model tested with a problem") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .ok, "Soapcap can hear your side."),
            Check("Call audio", .ok, "Soapcap can hear what the Mac is playing."),
            Check("Note model", .ok, "llama3.1:8b is ready to draft notes."),
            Check("Memory", .ok, "16 GB, about 10 GB free now."),
        ])
        $0.modelTest.show(.problem(model: "llama3.1:8b", reasons: ["ASSESSMENT is empty or \"Not addressed\""]), note: previewSampleNote)
    }
}

#Preview("Checks, model being tested") {
    sampleScreen {
        $0.phase = .checks([
            Check("Microphone", .ok, "Soapcap can hear your side."),
            Check("Call audio", .ok, "Soapcap can hear what the Mac is playing."),
            Check("Note model", .ok, "llama3.1:8b is ready to draft notes."),
            Check("Memory", .ok, "16 GB, about 10 GB free now."),
        ])
        $0.modelTest.show(.running("Drafting a SOAP note…", tokens: 240))
    }
}
