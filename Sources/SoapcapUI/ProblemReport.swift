import AppKit
import SwiftUI

/// An email to the developer with what is worth knowing about this copy
/// already written in, and nothing from a session.
struct ProblemReport {
    static let address = "pglockner@gmail.com"

    var version: AppVersion
    var macOS: String
    var memoryGB: Int
    var noteModel: String

    static var current: ProblemReport {
        ProblemReport(version: .current,
                      macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                      memoryGB: Int(ProcessInfo.processInfo.physicalMemory >> 30),
                      noteModel: SessionSettings().noteModel)
    }

    var subject: String { "Soapcap \(version.text): a problem" }

    /// This copy and this Mac, a line each.
    var details: String {
        """
        Soapcap \(version.text)
        macOS \(macOS)
        Memory \(memoryGB) GB
        Note model \(noteModel)
        """
    }

    var body: String {
        """
        What happened, and what you were doing just before:



        (Please don't include names or anything else from a session.)

        \(details)
        """
    }

    var mailURL: URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Self.address
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        // mailto wants spaces as %20; URLComponents leaves a + as it is,
        // which mail apps read as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }
}

/// The window Help › Report a Problem… opens: the address and this copy's
/// details to copy into any email, for those whose mail is in a browser,
/// or a new email in the Mac's mail app with both filled in.
struct ProblemReportView: View {
    static let window = "report"

    var report = ProblemReport.current
    @Environment(\.openURL) private var openURL
    /// Which of the two was copied last, so its button can say so.
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Write to the developer. Say what happened and what you were doing just before, but leave out names and anything else from a session.")
                .fixedSize(horizontal: false, vertical: true)
            copyable("Address", ProblemReport.address)
            copyable("Details to include", report.details)
            HStack {
                Text("Mail in a browser? Copy both into a new message.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open in Mail") { openURL(report.mailURL) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// A label over some text, with a button that copies the text.
    private func copyable(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button(copied == label ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = label
                }
                .frame(minWidth: 64)
            }
        }
    }
}

/// Opens the Report a Problem window.
struct ReportProblemButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Report a Problem…") { openWindow(id: ProblemReportView.window) }
    }
}
