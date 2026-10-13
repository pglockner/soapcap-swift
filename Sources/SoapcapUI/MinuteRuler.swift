import SwiftUI

/// The minutes of a session down the side of its transcript, as close
/// together as the height has room for, with a mark where the session was
/// paused. The minutes on screen are picked out, and each mark is a button
/// that goes there.
struct MinuteRuler: View {
    let index: MinuteIndex
    /// The first and last blocks on screen, once that is known.
    let visible: ClosedRange<Int>?
    /// Shows the block with the given id.
    let go: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("min").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                ForEach(MinuteIndex.steps, id: \.self) { marks(index.marks(every: $0)) }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Minutes of the session")
    }

    private func marks(_ marks: [MinuteIndex.Mark]) -> some View {
        let shown = visible.map { MinuteIndex.shown(marks, visible: $0) } ?? []
        return VStack(spacing: 0) {
            ForEach(marks, id: \.self) { mark in
                if mark != marks.first { Spacer(minLength: 2) }
                if let pause = mark.pause {
                    PillButton(showsAtRest: false, action: { go(mark.block) }) {
                        Image(systemName: "pause.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(minWidth: 18)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                    }
                    .help(pause.textWithTime)
                    .accessibilityLabel(pause.textWithTime)
                } else {
                    let isShown = shown.contains(mark.minute)
                    PillButton(showsAtRest: isShown, action: { go(mark.block) }) {
                        Text(mark.minute, format: .number)
                            .font(.caption.monospacedDigit())
                            .fontWeight(isShown ? .semibold : .regular)
                            .foregroundStyle(isShown ? .primary : .secondary)
                            .frame(minWidth: 18)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                    }
                    .help("Go to minute \(mark.minute)")
                    .accessibilityLabel("Minute \(mark.minute)")
                    .accessibilityValue(isShown ? "on screen" : "")
                }
            }
        }
    }
}
