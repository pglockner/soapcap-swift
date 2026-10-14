import AppKit
import SwiftUI

/// The version this copy of the app says it is, from its Info.plist.
struct AppVersion: Equatable {
    /// "0.11.0"; empty for a copy run from the package, which has no Info.plist.
    let marketing: String
    /// The build number, which rises with every commit.
    let build: String

    static let current = AppVersion(
        marketing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")

    /// "0.11.0 (149)", as the About box writes it.
    var text: String { build.isEmpty ? marketing : "\(marketing) (\(build))" }
}

/// Every version below 1.0 is a beta. It says so on the Ready screen (the
/// bar has no room to spare at the window's narrowest), and once for
/// each version in a notice that has to be acknowledged, so the notice
/// comes back after an update and goes for good at 1.0.
enum Beta {
    /// A version with no number, as a copy run from the package has, counts
    /// as a beta too: it is a development copy.
    static func isBeta(_ version: String) -> Bool {
        guard let major = Int(version.split(separator: ".").first ?? "") else { return true }
        return major == 0
    }

    /// Whether the notice is still to be acknowledged for this version. A
    /// copy with no version has nothing to acknowledge.
    static func needsNotice(version: String, seen: String) -> Bool {
        !version.isEmpty && isBeta(version) && seen != version
    }

    /// What the notice says, one point to a line, with a symbol for each.
    /// Help shows the same points.
    static let points: [(symbol: String, text: String)] = [
        ("hammer", "This is pre-release software, for testing. Expect rough edges, and use Help › Report a Problem when something goes wrong."),
        ("doc.text.magnifyingglass", "Read every note before you use it. A language model drafts it, and it can leave out what was said or add what wasn't. What goes in the record is your responsibility."),
        ("lock", "Sessions stay on this Mac. Nothing from a session is sent anywhere, and nothing is saved unless you ask."),
    ]
}

/// The points of the beta notice, as a list.
struct BetaPoints: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Beta.points, id: \.symbol) { point in
                Label {
                    Text(point.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: point.symbol).foregroundStyle(.orange).frame(width: 22)
                }
            }
        }
    }
}

/// Shown over the window until this version's notice is acknowledged.
struct BetaNoticeView: View {
    let version: String
    let understood: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Soapcap \(version) is a beta").font(.title2.weight(.semibold))
            BetaPoints()
            HStack {
                Text("You'll see this again after each update.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("I understand", action: understood).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Marks the app as a beta at the foot of the Ready screen.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(.orange.opacity(0.6)))
            .help("Pre-release software: read every note before you use it")
    }
}
