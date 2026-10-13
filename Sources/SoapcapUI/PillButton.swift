import SwiftUI

/// A word that can be clicked. It sits on a quiet pill, as a button at rest
/// does, which deepens under the pointer; the pointer becomes a hand.
struct PillButton<Label: View>: View {
    /// Whether the pill shows at rest, or only under the pointer.
    var showsAtRest = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .background(.primary.opacity(isHovered ? 0.18 : showsAtRest ? 0.09 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerStyle(.link)
    }
}
