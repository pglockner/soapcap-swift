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
                    Button { go(step) } label: { label(step) }.buttonStyle(.plain)
                        .help("Go back to the \(Self.title(step).lowercased())")
                } else {
                    label(step)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func label(_ step: SessionModel.Stage) -> some View {
        let isDone = step.rawValue < stage.rawValue
        return HStack(spacing: 4) {
            if isDone { Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true) }
            Text(Self.title(step))
        }
        .fontWeight(step == stage ? .semibold : .regular)
        .foregroundStyle(step == stage ? .primary : isDone ? .secondary : .tertiary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(step == stage ? "current step" : isDone ? "done" : "not yet")
    }

    static func title(_ step: SessionModel.Stage) -> String {
        switch step {
        case .record: "Record"
        case .transcript: "Transcript"
        case .note: "Note"
        }
    }
}
