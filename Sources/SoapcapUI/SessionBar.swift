import SwiftUI

/// The bar across the top of the window: the app's name, the three steps of
/// a session with the one in hand picked out, and the way to the checks and
/// to Settings.
struct SessionBar: ToolbarContent {
    @ObservedObject var m: SessionModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text("Soapcap").font(.headline)
            }
            .padding(.trailing, 4)
            // A bar item takes the clicks that land on it; the name gives them
            // back, so that the window can be dragged by it.
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
        }
        // A name is not a control, so it gets no glass behind it.
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) {
            StageBar(stage: m.stage, canGo: { m.canGo(to: $0) }, go: { m.go(to: $0) })
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Check", systemImage: "checklist") { m.diagnose() }
                .disabled(!m.canCheck)
                .help("Check that Soapcap can hear both sides and draft a note")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .help("Settings")
        }
    }
}

/// Record, Transcript, Note: where a session is, and a way back to the
/// transcript once there is a note.
struct StageBar: View {
    let stage: SessionModel.Stage
    let canGo: (SessionModel.Stage) -> Bool
    let go: (SessionModel.Stage) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SessionModel.Stage.allCases, id: \.self) { step in
                if step != .record {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                // Only a step that can be gone to is a button: a disabled
                // one would grey out the step the session is on.
                if canGo(step) {
                    StepButton(action: { go(step) }) { label(step, canGo: true) }
                        .help("Go to the \(Self.title(step).lowercased())")
                } else {
                    label(step, canGo: false).gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// A step that is done, or that there is something to go to (a note,
    /// seen from the transcript), is ticked and reads as within reach.
    private func label(_ step: SessionModel.Stage, canGo: Bool) -> some View {
        let isReached = step.rawValue < stage.rawValue || canGo
        return HStack(spacing: 4) {
            if isReached { Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true) }
            Text(Self.title(step))
        }
        .fontWeight(step == stage ? .semibold : .regular)
        // Full strength for where the session is and for where it can go;
        // a step that is only done, or not reached, stands back.
        .foregroundStyle(step == stage || canGo ? .primary : isReached ? .secondary : .tertiary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(step == stage ? "current step" : isReached ? "done" : "not yet")
    }

    static func title(_ step: SessionModel.Stage) -> String {
        switch step {
        case .record: "Record"
        case .transcript: "Transcript"
        case .note: "Note"
        }
    }
}

/// A step that can be gone to: it lights up under the pointer, and the
/// pointer becomes a hand, as it does over a link.
private struct StepButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.primary.opacity(isHovered ? 0.1 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerStyle(.link)
        .padding(.horizontal, -7)
    }
}
