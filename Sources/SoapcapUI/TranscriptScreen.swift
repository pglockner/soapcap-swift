import SwiftUI

/// The transcript once the session has stopped: De-identify or Save
/// transcript above it, and the format and Draft note below.
struct TranscriptScreen: View {
    @EnvironmentObject var m: SessionModel
    /// Asked before a note that hasn't been kept is drafted over.
    @State private var asksToReplace = false
    /// Whether the panel that saves the transcript is up, and what went
    /// wrong if a save failed.
    @State private var savesTranscript = false
    @State private var saveFailed = false
    @State private var saveFailure = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transcript").font(.headline)
                Spacer()
                // The one thing the app ever writes to disk, and only a
                // transcript that de-identifying has been over: until then,
                // the button in its place is the way to have that done.
                if m.transcriptIsDeidentified {
                    Button("Save transcript…") { savesTranscript = true }
                        .controlSize(.small)
                        .help("Save the de-identified transcript as a text file, wherever you choose")
                } else if m.canDeidentify {
                    Button("De-identify") { m.deidentify() }
                        .controlSize(.small)
                        .help("Replace names and other identifying details with tokens, in the transcript and in the note. Then the transcript can be saved.")
                }
            }
            WarningBanner(text: m.warning)
            TranscriptView(text: m.transcript, times: m.lineTimes, pauses: m.pauses)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            // Memory changes as apps open and close, so this is asked again every few seconds.
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                if let advice = m.memoryAdvice {
                    Label(advice, systemImage: "memorychip").font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Picker("Format", selection: $m.format) {
                    ForEach(SessionModel.formats, id: \.self) { Text($0.uppercased()) }
                }.pickerStyle(.segmented).fixedSize()
                Button(m.hasUnkeptNote ? "Draft again" : "Draft note") {
                    if m.hasUnkeptNote { asksToReplace = true } else { m.draftIfRoom() }
                }
                // Return doesn't draft over a note that hasn't been kept.
                .keyboardShortcut(m.hasUnkeptNote ? nil : .defaultAction)
                .alert("Replace the note you haven't kept?", isPresented: $asksToReplace) {
                    Button("Cancel", role: .cancel) {}
                    Button("Draft again", role: .destructive) { m.draftIfRoom() }
                } message: {
                    Text("Drafting again writes a new note in its place, and the one you have can't be got back. To hold on to it, go to the note and choose Keep first.")
                }
                NoteModelPicker()
                Spacer()
                LeaveButton(m: m)
            }
        }
        .alert("Not enough free memory", isPresented: Binding(get: { m.memoryQuestion != nil }, set: { if !$0 { m.memoryQuestion = nil } })) {
            // Return should not start a draft the Mac has no room for.
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
            Button("Draft anyway") { m.draft() }
        } message: {
            Text(m.memoryQuestion ?? "")
        }
        .fileExporter(isPresented: $savesTranscript, document: m.transcriptFile, contentType: .plainText,
                      defaultFilename: TranscriptFile.name) { result in
            // Closing the panel without saving is not a failure.
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                saveFailure = error.localizedDescription
                saveFailed = true
            }
        }
        .alert("The transcript was not saved", isPresented: $saveFailed) {} message: {
            Text(saveFailure)
        }
    }
}
