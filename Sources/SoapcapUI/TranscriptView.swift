import SwiftUI

/// A session's transcript. When each line's time is known, the minute stands
/// beside the text and a ruler of minutes down the side goes to any of them.
struct TranscriptView: View {
    let text: String
    /// When each line began, in seconds of the session.
    let times: [Int]

    var body: some View {
        if let index = MinuteIndex(text: text, times: times) {
            MinuteBlocks(index: index)
        } else {
            ReadingText(text: text)
        }
    }
}

/// The transcript a minute at a time. Each minute is one piece of text, so
/// that a selection can run over the whole of it.
private struct MinuteBlocks: View {
    let index: MinuteIndex
    @State private var position = ScrollPosition(idType: Int.self)
    /// The first and last minutes on screen.
    @State private var visible: ClosedRange<Int>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(index.blocks) { block in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            minute(block.minute)
                            Text(block.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
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
