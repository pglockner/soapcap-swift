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
            // A warning sign in orange when the last check found something
            // in the way: a different shape, not only a different colour.
            Button("Check", systemImage: m.needsAttention ? "exclamationmark.triangle.fill" : "checklist") { m.diagnose() }
                .foregroundStyle(m.needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .disabled(!m.canCheck)
                .help(m.needsAttention ? "Something needs attention. Click to see what"
                      : "Check that Soapcap can hear both sides and draft a note")
                .accessibilityValue(m.needsAttention ? "needs attention" : "")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .help("Settings")
        }
    }
}

/// Record, Transcript, Note: where a session is, and a way back to the
/// transcript once there is a note. Drawn as Activity Monitor's segments
/// are: the step in hand on a pill, the ones that can be gone to at full
/// strength, and the rest dimmed, as a segment that can't be picked is.
struct StageBar: View {
    let stage: SessionModel.Stage
    let canGo: (SessionModel.Stage) -> Bool
    let go: (SessionModel.Stage) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SessionModel.Stage.allCases, id: \.self) { step in
                // Only a step that can be gone to is a button: a disabled
                // one would grey out the step the session is on.
                if canGo(step) {
                    PillButton(showsAtRest: false, action: { go(step) }) { label(step) }
                        .help("Go to the \(Self.title(step).lowercased())")
                } else {
                    label(step).gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
                }
            }
        }
        // The pill of the step in hand sits just inside the bar's own.
        .padding(.horizontal, 4)
    }

    private func label(_ step: SessionModel.Stage) -> some View {
        Text(Self.title(step))
            .foregroundStyle(step == stage || canGo(step) ? .primary : .tertiary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.primary.opacity(step == stage ? 0.1 : 0), in: Capsule())
            .accessibilityValue(step == stage ? "current step" : canGo(step) ? "" : "not available")
    }

    static func title(_ step: SessionModel.Stage) -> String {
        switch step {
        case .record: "Record"
        case .transcript: "Transcript"
        case .note: "Note"
        }
    }
}
