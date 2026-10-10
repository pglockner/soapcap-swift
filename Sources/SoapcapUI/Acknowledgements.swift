import SwiftUI

/// One project this app builds on, from Resources/Credits/credits.json.
struct Credit: Decodable, Identifiable, Equatable {
    let name: String
    let by: String
    let role: String
    let url: URL
    let license: String
    let licenseFile: String
    /// Its name in Package.resolved, for the ones the build pulls in.
    let package: String?

    var id: String { name }

    private static let folder = Bundle.module.resourceURL?.appending(path: "Credits")

    static let all: [Credit] = {
        guard let url = folder?.appending(path: "credits.json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Credit].self, from: data)) ?? []
    }()

    var licenseText: String? {
        Self.folder.flatMap { try? String(contentsOf: $0.appending(path: "licenses/\(licenseFile)"), encoding: .utf8) }
    }
}

/// Who made what this app is built from, and under which licence.
struct AcknowledgementsView: View {
    var body: some View {
        // A plain stack rather than a List: with these rows, whose height
        // changes when a licence is shown, a List crashed as it was drawn.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Credit.all) { credit in
                    CreditRow(credit: credit)
                    Divider()
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct CreditRow: View {
    let credit: Credit
    @State private var showsLicence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Link(credit.name, destination: credit.url).font(.headline)
                Text("by \(credit.by)").foregroundStyle(.secondary)
                Spacer()
                Text(credit.license).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(credit.role).fixedSize(horizontal: false, vertical: true)
            Button(showsLicence ? "Hide licence" : "Show licence") { showsLicence.toggle() }
                .buttonStyle(.link).font(.callout)
            if showsLicence {
                Text(credit.licenseText ?? "The licence text is missing from this build; see \(credit.url.absoluteString).")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
    }
}

/// The app-menu item that opens the window.
struct AcknowledgementsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View { Button("Acknowledgements") { openWindow(id: "acknowledgements") } }
}

#Preview("Acknowledgements") { AcknowledgementsView().frame(width: 560, height: 520) }
