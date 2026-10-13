import SwiftUI

/// Text to read and to copy from: a note, or a transcript whose lines have
/// no times.
struct ReadingText: View {
    let text: String

    var body: some View {
        ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            .readingBox()
    }
}

extension View {
    /// The quiet grey box that text to be read sits in.
    func readingBox() -> some View {
        background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}
