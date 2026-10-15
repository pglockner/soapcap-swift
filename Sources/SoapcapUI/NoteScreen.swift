import SwiftUI

/// The drafted note, with Keep, Regenerate and the model that drafts.
struct NoteScreen: View {
    @EnvironmentObject var m: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\((m.draftedFormat.isEmpty ? m.format : m.draftedFormat).uppercased()) note").font(.headline)
            WarningBanner(text: m.warning)
            ReadingText(text: m.note)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(m.copied ? "Copied" : "Keep") { m.keep() }.keyboardShortcut(.defaultAction)
                Button("Regenerate") { m.draft() }
                NoteModelPicker()
                Spacer()
                LeaveButton(m: m)
            }
        }
    }
}
