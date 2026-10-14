import SoapcapCore
import SwiftUI

// Drafting, with its steps and memory charts, and the note.

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

#Preview("Drafting, memory full") {
    sampleScreen {
        $0.phase = .note
        $0.phase = .working("Drafting the Objective with Bonsai…")
        $0.draftSteps = ["Loading Bonsai…", "Reading the transcript with Bonsai…", "Drafting a SOAP note with Bonsai…", "Drafting the Objective with Bonsai…"]
        $0.draftTokens = 96
        $0.draftRun.show(trail: previewTrail(from: 40, to: 6, swapGB: 6.4))
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
