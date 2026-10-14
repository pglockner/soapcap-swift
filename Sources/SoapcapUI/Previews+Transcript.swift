import SoapcapCore
import SwiftUI

// The transcript: de-identified or not, short of memory, and long sessions
// with the minute index and pauses.

#Preview("Transcript") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.lineTimes = [2, 9, 21, 24]
        $0.notice = "Transcript: 2 identifying details replaced (first name, date)"
        $0.transcriptIsDeidentified = true
    }
}

#Preview("Transcript, dark") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.lineTimes = [2, 9, 21, 24]
        $0.notice = "Transcript: 2 identifying details replaced (first name, date)"
        $0.transcriptIsDeidentified = true
    }
    .preferredColorScheme(.dark)
}

#Preview("Transcript, not de-identified") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.warning = "Not de-identified. This transcript still contains names and other identifying details.\nThe model's files could not be read."
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

#Preview("Transcript, gone back to from a note not kept") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.note = "53 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported sleeping better."
    }
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
    sampleScreen {
        longSession($0, minutes: 7, pauses: [SessionPause(at: 40, length: 95)])
        $0.notice = "Transcript: 2 identifying details replaced (first name, date)"
        $0.transcriptIsDeidentified = true
    }
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
