import SoapcapCore
import SwiftUI

/// What the app needs in order to record, and what to do about anything missing.
struct ChecksView: View {
    let checks: [Check]
    /// Trying the note model, offered on its row once the model is there.
    @ObservedObject var test: ModelTest
    let model: String
    /// Does what a row's button stands for.
    let perform: (Check.Fix.Action) -> Void
    let again: () -> Void
    let back: () -> Void
    @Environment(\.openSettings) private var openSettings

    /// A row's status, with the trial of the note model counted in: a model
    /// that is there but drafted a faulty note is not ready.
    private func status(of check: Check) -> Check.Status {
        if check.title == "Note model", check.status == .ok, case .problem(let tested, _) = test.state, tested == model { return .warning }
        return check.status
    }

    /// While a permission is missing this screen is the way in, not a report.
    private var isSetup: Bool {
        checks.contains { ["Microphone", "Call audio"].contains($0.title) && $0.status != .ok }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(checks.allSatisfy { status(of: $0) == .ok } ? "Everything is ready" : isSetup ? "Set up Soapcap" : "Some things need attention")
                .font(.title2.bold())
            if isSetup {
                Text("Soapcap needs two permissions from macOS before it can record. Each button below says what you are about to see.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(checks) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            icon(status(of: check)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.title).fontWeight(.medium)
                                Text(check.detail).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let fix = check.fix {
                                    Button(fix.label) {
                                        if fix.action == .showSettings { openSettings() } else { perform(fix.action) }
                                    }.controlSize(.small).padding(.top, 2)
                                }
                                if check.title == "Note model", check.status != .failed {
                                    ModelTestView(test: test, model: model).controlSize(.small).padding(.top, 2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            // In a box of its own, as the transcript and the note are: a row
            // cut off by its edge shows that there are more below.
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                if isSetup {
                    Button("Check again") { again() }
                    Spacer()
                    Button("Not now") { back() }
                } else {
                    Button("Back") { back() }.keyboardShortcut(.defaultAction)
                    Button("Check again") { again() }
                }
            }
        }
    }

    @ViewBuilder private func icon(_ status: Check.Status) -> some View {
        switch status {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
