import SwiftUI

/// A session's transcript. When each line's time is known, the minute stands
/// beside the text and a ruler of minutes down the side goes to any of them.
struct TranscriptView: View {
    let text: String
    /// When each line began, in seconds of the session.
    let times: [Int]
    /// When the session was paused, in the same seconds.
    var pauses: [Int] = []

    var body: some View {
        if let index = MinuteIndex(text: text, times: times, pauses: pauses) {
            MinuteBlocks(index: index)
        } else {
            ReadingText(text: text)
        }
    }
}

/// One turn of the transcript, "Therapist: How was the week?", with the
/// speaker's name picked out so that the eye finds who is talking.
private struct TurnLine: View {
    let line: String

    var body: some View {
        // The name runs up to the first colon; a line without one has no name.
        let cut = line.range(of: ": ")?.upperBound ?? line.startIndex
        Text("\(Text(line[..<cut]).fontWeight(.semibold))\(String(line[cut...]))")
    }
}

/// The transcript a minute at a time, each turn a speaker took standing a
/// little apart from the next so that the back and forth can be seen.
private struct MinuteBlocks: View {
    /// The room between one turn and the next.
    private static let gap: CGFloat = 8

    let index: MinuteIndex
    @State private var position = ScrollPosition(idType: Int.self)
    /// The first and last minutes on screen.
    @State private var visible: ClosedRange<Int>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                // Not a lazy stack: going to a minute needs to know where
                // every one of them is, and a session has only so many.
                VStack(alignment: .leading, spacing: Self.gap) {
                    ForEach(index.blocks) { block in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            minute(block.minute)
                            VStack(alignment: .leading, spacing: Self.gap) {
                                ForEach(block.lines.indices, id: \.self) { line in
                                    TurnLine(line: block.lines[line]).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(8, for: .scrollContent)
            .scrollPosition($position)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.05) { minutes in
                if let first = minutes.min(), let last = minutes.max() { visible = first...last }
            }
            if index.blocks.count > 1 {
                Divider()
                MinuteRuler(index: index, visible: visible) { minute in
                    withAnimation(reduceMotion ? nil : .default) { position.scrollTo(id: minute, anchor: .top) }
                }
            }
        }
        .readingBox()
    }

    /// The minute a block began in, as wide as the widest of them.
    private func minute(_ minute: Int) -> some View {
        Text(SessionClock.text((index.blocks.last?.minute ?? minute) * 60)).hidden()
            .overlay(alignment: .trailing) { Text(SessionClock.text(minute * 60)) }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityElement()
            .accessibilityLabel("Minute \(minute)")
    }
}
