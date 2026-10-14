import SoapcapCapture
import SoapcapCore
import SwiftUI

// What the previews share. The previews themselves are in a file per
// screen (Previews+Session, +Transcript, +Note, +Checks, +Settings, +Beta),
// since the canvas shows only those of the file that is open.

@MainActor func sampleScreen(_ set: (SessionModel) -> Void) -> some View {
    let m = SessionModel()
    set(m)
    return ContentView().environmentObject(m).frame(width: 560, height: 420)
}

let previewLines = [
    LiveLine(speaker: "Therapist", text: "How has your sleep been since we last spoke?", isFinal: true),
    LiveLine(speaker: "Client", text: "Better, mostly. The breathing exercises helped the first few nights.", isFinal: true),
    LiveLine(speaker: "Therapist", text: "That's good to hear.", isFinal: true),
    LiveLine(speaker: "Client", text: "Then on Thursday I had the argument with my", isFinal: false),
]

let previewSampleNote = "9 minutes, telehealth\n\nSUBJECTIVE:\nThe client reported that the chest tightness came back twice this week.\n\nOBJECTIVE:\nOn time via video. Cooperative. Affect constricted; mood stressed. No SI/HI reported.\n\nASSESSMENT:\nSymptoms remain consistent with the generalized anxiety the client described.\n\nPLAN:\nPractise the breathing exercise twice a day; review in two weeks."

/// A model test in a given state, as Settings and the checks screen show it.
@MainActor func testedModel(_ state: ModelTest.State, note: String? = previewSampleNote) -> ModelTest {
    let test = SessionModel().modelTest
    test.show(state, note: note)
    return test
}
