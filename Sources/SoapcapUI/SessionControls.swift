import SwiftUI

// What more than one screen of a session shows.

/// Ends a session. A session that is stopped can't be taken up again, so the
/// button is red and Return doesn't press it.
struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button("Stop", action: action).buttonStyle(.borderedProminent).tint(.red)
    }
}

/// Starts afresh. While the session holds something that hasn't been kept it
/// says Discard, in red, and asks first; once the note is on the clipboard,
/// leaving is no longer throwing anything away.
struct LeaveButton: View {
    @ObservedObject var m: SessionModel
    @State private var asks = false

    var body: some View {
        Button {
            if m.hasUnkeptWork { asks = true } else { m.newSession() }
        } label: {
            Text(m.hasUnkeptWork ? "Discard" : "New session").foregroundStyle(m.hasUnkeptWork ? Color.red : Color.primary)
        }
        .alert("Discard this session?", isPresented: $asks) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { m.newSession() }
        } message: {
            Text(m.note.isEmpty ? "The transcript can't be got back." : "The transcript and the note can't be got back. To hold on to the note, choose Keep first.")
        }
    }
}

/// Shown above text that was meant to be de-identified and was not; nothing
/// when `text` is empty.
struct WarningBanner: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
