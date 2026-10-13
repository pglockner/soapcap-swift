import SoapcapCapture
import SoapcapCore
import SoapcapNote
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

#Preview("Ready, wide window") {
    ContentView().environmentObject(SessionModel()).frame(width: 900, height: 420)
}

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
        $0.lineTimes = [2, 9, 21, 24]
        $0.notice = "Transcript: 2 identifying details replaced (first name, date)"
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

/// Memory readings for a draft's two charts: free memory falling from one
/// percentage to another while the model loads, and swap rising to `swapGB`.
private func previewTrail(from: Int, to: Int, swapGB: Double = 0) -> [MemoryStatus] {
    (0..<70).map { step in
        let part = min(1, Double(step) / 45)
        let free = Double(from) + (Double(to) - Double(from)) * part + (step % 3 == 0 ? 1 : 0)
        return MemoryStatus(totalBytes: 16 << 30, freePercent: Int(free),
                            swapUsedBytes: UInt64(swapGB * part * part * 1_073_741_824), swapTotalBytes: 8 << 30)
    }
}

#Preview("Drafting") {
    sampleScreen {
        $0.phase = .note
        $0.phase = .working("Drafting a SOAP note with llama3.1:8b…  412 tokens")
        $0.draftSteps = ["Loading llama3.1:8b…", "Drafting a SOAP note with llama3.1:8b…"]
        $0.draftTokens = 412
        $0.draftRun.show(trail: previewTrail(from: 54, to: 38))
    }
}

#Preview("Drafting, memory full") {
    sampleScreen {
        $0.phase = .note
        $0.phase = .working("Drafting the Objective with Bonsai…")
        $0.draftSteps = ["Loading Bonsai…", "Reading the transcript with Bonsai…", "Drafting a SOAP note with Bonsai…", "Drafting the Objective with Bonsai…"]
        $0.draftTokens = 96
        $0.draftRun.show(trail: previewTrail(from: 40, to: 6, swapGB: 6.4))
    }
}

#Preview("Transcript, memory short") {
    let defaults = UserDefaults(suiteName: "soapcap-preview")!
    defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
    let m = SessionModel(settings: SessionSettings(defaults: defaults), memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: 41) })
    m.phase = .transcript
    m.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    return ContentView().environmentObject(m).frame(width: 560, height: 420)
}

#Preview("Transcript, memory very short") {
    let defaults = UserDefaults(suiteName: "soapcap-preview")!
    defaults.set("bonsai", forKey: SessionSettings.Key.noteModel)
    let m = SessionModel(settings: SessionSettings(defaults: defaults), memory: { MemoryStatus(totalBytes: 16 << 30, freePercent: 30, swapUsedBytes: 7 << 30, swapTotalBytes: 8 << 30) })
    m.phase = .transcript
    m.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    m.draftIfRoom()
    return ContentView().environmentObject(m).frame(width: 560, height: 420)
}

#Preview("Note") {
    sampleScreen {
        $0.phase = .note
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better since starting the breathing exercises.\n\nOBJECTIVE:\nOn time via video. Engaged. Affect congruent; mood stressed. Speech clear. Thought process linear. Insight good; judgment intact. No psychomotor abnormalities. No SI/HI reported.\n\nASSESSMENT:\nSleep is improving; conflict at home remains a stressor.\n\nPLAN:\nContinue the breathing exercises nightly. Return next week."
        $0.notice = "No Client lines in the transcript — the Subjective and the Objective are left for you to complete."
    }
}

#Preview("Note, copied") {
    sampleScreen {
        $0.phase = .note
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better since starting the breathing exercises.\n\nOBJECTIVE:\nOn time via video. Engaged. Affect congruent; mood stressed. Speech clear. Thought process linear. Insight good; judgment intact. No psychomotor abnormalities. No SI/HI reported.\n\nASSESSMENT:\nSleep is improving; conflict at home remains a stressor.\n\nPLAN:\nContinue the breathing exercises nightly. Return next week."
        $0.copied = true
    }
}

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

private let previewSampleNote = "9 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported that the chest tightness came back twice this week.\n\nOBJECTIVE:\nOn time via video. Cooperative. Affect constricted; mood stressed. No SI/HI reported.\n\nASSESSMENT:\nSymptoms remain consistent with the generalized anxiety the client described.\n\nPLAN:\nPractise the breathing exercise twice a day; review in two weeks."

@MainActor private func testedModel(_ state: ModelTest.State, note: String? = previewSampleNote) -> ModelTest {
    let test = SessionModel().modelTest
    test.show(state, note: note)
    return test
}

#Preview("Settings, model tested good") { SettingsView(test: testedModel(.good(model: "llama3.1:8b", seconds: 48))) }

#Preview("Settings, model being tested") { SettingsView(test: testedModel(.running("Drafting a SOAP note with llama3.1:8b…"), note: nil)) }

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

#Preview("Error") {
    sampleScreen {
        $0.phase = .error("Soapcap can't use the microphone. Turn it on for Soapcap in System Settings > Privacy & Security > Microphone, then quit and reopen Soapcap.")
    }
}

#Preview("Recording, dark") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 754; $0.liveLines = previewLines }.preferredColorScheme(.dark)
}

#Preview("Transcript, dark") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.lineTimes = [2, 9, 21, 24]
        $0.notice = "Transcript: 2 identifying details replaced (first name, date)"
    }
    .preferredColorScheme(.dark)
}

#Preview("Transcribing, just started") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 4 }
}

#Preview("Settings, the end") { SettingsView(test: SessionModel().modelTest).defaultScrollAnchor(.bottom) }

#Preview("Transcript, gone back to from a note not kept") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better."
    }
}

#Preview("Drafting again, with a note already there") {
    sampleScreen {
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better."
        $0.phase = .note
        $0.phase = .working("Drafting a SOAP note with llama3.1:8b…  188 tokens")
        $0.draftSteps = ["Loading llama3.1:8b…", "Drafting a SOAP note with llama3.1:8b…"]
        $0.draftTokens = 188
        $0.draftRun.show(trail: previewTrail(from: 50, to: 31))
    }
}

#Preview("Finishing a session") {
    sampleScreen { $0.phase = .working("Finishing transcription…") }
}

#Preview("Drafting, memory getting short, light") {
    sampleScreen {
        $0.phase = .note
        $0.phase = .working("Drafting a SOAP note with Bonsai…  240 tokens")
        $0.draftSteps = ["Loading Bonsai…", "Reading the transcript with Bonsai…", "Drafting a SOAP note with Bonsai…"]
        $0.draftTokens = 240
        $0.draftRun.show(trail: previewTrail(from: 48, to: 19, swapGB: 3.6))
    }
    .preferredColorScheme(.light)
}

/// A made-up session of so many minutes, for the transcript's minute index.
@MainActor private func longSession(_ m: SessionModel, minutes: Int, pauses: [SessionPause] = []) {
    let said: [(who: String, what: String)] = [
        ("Therapist", "How has your sleep been since we last spoke?"),
        ("Client", "Better, mostly. The breathing exercises helped the first few nights, and then on Thursday it all went sideways again."),
        ("Therapist", "What happened on Thursday?"),
        ("Client", "I had the argument with my sister about the house. I didn't sleep at all after that, I just lay there going over what I should have said."),
        ("Therapist", "That sounds exhausting."),
        ("Client", "It was. And then work the next day."),
        ("Therapist", "When you were lying awake, did you try any of what we practised?"),
        ("Client", "The counting, for a bit. It works until I notice that it's working, if that makes sense."),
        ("Therapist", "It does. That's very common."),
    ]
    var lines: [String] = [], times: [Int] = []
    var time = 3
    while time < minutes * 60 {
        let line = said[lines.count % said.count]
        lines.append(line.who + ": " + line.what)
        times.append(time)
        time += 3 + line.what.count / 14
    }
    m.transcript = lines.joined(separator: "\n")
    m.lineTimes = times
    m.pauses = pauses
    m.elapsed = minutes * 60
    m.phase = .transcript
}

#Preview("Transcript, a long session") {
    sampleScreen { longSession($0, minutes: 53) }
}

#Preview("Transcript, a long session, at its end") {
    sampleScreen { longSession($0, minutes: 53) }.defaultScrollAnchor(.bottom)
}

#Preview("Transcript, a short session") {
    sampleScreen { longSession($0, minutes: 7, pauses: [SessionPause(at: 40, length: 95)]) }
}

#Preview("Transcript, a session paused twice") {
    sampleScreen { longSession($0, minutes: 53, pauses: [SessionPause(at: 760, length: 95), SessionPause(at: 1875, length: 600)]) }
}

#Preview("Transcript, with a pause in it") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.lineTimes = [2, 9, 81, 84]
        $0.pauses = [SessionPause(at: 15, length: 95)]
    }
}

#Preview("Ready, with something needing attention") {
    sampleScreen { $0.needsAttention = true }
}
