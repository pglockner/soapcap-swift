import SwiftUI

// Ready, Transcribing and Paused, and what follows Stop.

#Preview("Ready") { sampleScreen { _ in } }

#Preview("Ready, wide window") {
    ContentView().environmentObject(SessionModel()).frame(width: 900, height: 420)
}

#Preview("Ready, with something needing attention") {
    sampleScreen { $0.needsAttention = true }
}

#Preview("Recording") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Recording, dark") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 754; $0.liveLines = previewLines }.preferredColorScheme(.dark)
}

#Preview("Transcribing, just started") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 4 }
}

#Preview("Paused") {
    sampleScreen { $0.phase = .paused; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Finishing a session") {
    sampleScreen { $0.phase = .working("Finishing transcription…") }
}

#Preview("Error") {
    sampleScreen {
        $0.phase = .error("Soapcap can't use the microphone. Turn it on for Soapcap in System Settings > Privacy & Security > Microphone, then quit and reopen Soapcap.")
    }
}
