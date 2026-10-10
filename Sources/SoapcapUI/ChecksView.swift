import SoapcapCore
import SwiftUI

/// What the app needs in order to record, and what to do about anything missing.
struct ChecksView: View {
    let checks: [Check]
    let again: () -> Void
    let back: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(checks.allSatisfy { $0.status == .ok } ? "Everything is ready" : "Some things need attention")
                .font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(checks) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            icon(check.status).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.title).fontWeight(.medium)
                                Text(check.detail).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let fix = check.fix {
                                    Button(fix.label) { openURL(fix.url) }.controlSize(.small).padding(.top, 2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Back") { back() }.keyboardShortcut(.defaultAction)
                Button("Check again") { again() }
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
