import AppKit
import SwiftUI

/// The help page, from Resources/Help/help.md: a section for each `## `
/// heading, holding paragraphs, lists of `- ` lines and steps of `1. `
/// lines. Text within a line may use bold, code and links.
struct HelpPage {
    enum Block: Hashable {
        case paragraph(String)
        case list([String])
        case steps([String])
    }

    /// "2. Unzip it" → "Unzip it"; nil for a line that isn't a step.
    static func step(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), dot > line.startIndex, line[..<dot].allSatisfy(\.isNumber),
              line[line.index(after: dot)...].hasPrefix(" ") else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }

    struct Section: Identifiable, Hashable {
        let title: String
        let blocks: [Block]
        var id: String { title }
    }

    static let sections: [Section] = {
        guard let url = Bundle.module.resourceURL?.appending(path: "Help/help.md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return sections(from: text)
    }()

    /// Anything above the first section, such as the page's own title, is left out.
    static func sections(from markdown: String) -> [Section] {
        var sections: [Section] = []
        var title: String?
        var blocks: [Block] = []
        var lines: [String] = []

        func endBlock() {
            guard !lines.isEmpty else { return }
            if lines.allSatisfy({ $0.hasPrefix("- ") }) {
                blocks.append(.list(lines.map { String($0.dropFirst(2)) }))
            } else if case let steps = lines.compactMap(step), steps.count == lines.count {
                blocks.append(.steps(steps))
            } else {
                blocks.append(.paragraph(lines.joined(separator: " ")))
            }
            lines = []
        }
        func endSection() {
            endBlock()
            if let title { sections.append(Section(title: title, blocks: blocks)) }
            blocks = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                endSection()
                title = String(line.dropFirst(3))
            } else if line.isEmpty {
                endBlock()
            } else if title != nil {
                lines.append(line)
            }
        }
        endSection()
        return sections
    }
}

/// The window Help › Soapcap Help opens.
struct HelpView: View {
    var sections = HelpPage.sections
    var isBeta = Beta.isBeta(AppVersion.current.marketing)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isBeta {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This is a beta").font(.title3.weight(.semibold))
                        BetaPoints()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title).font(.title3.weight(.semibold))
                        ForEach(section.blocks, id: \.self) { block in
                            switch block {
                            case .paragraph(let text):
                                inline(text)
                            case .list(let items):
                                marked(items) { _ in "•" }
                            case .steps(let items):
                                marked(items) { "\($0 + 1)." }
                            }
                        }
                    }
                }
                ReportProblemButton().padding(.top, 4)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
        .frame(minWidth: 480, minHeight: 400)
    }

    /// Items one under another, each after its mark: a bullet, or its number.
    private func marked(_ items: [String], mark: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(mark(index)).foregroundStyle(.secondary).monospacedDigit()
                    inline(item)
                }
            }
        }
    }

    private func inline(_ text: String) -> some View {
        let styled = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(styled).fixedSize(horizontal: false, vertical: true)
    }
}

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

    var body: String {
        """
        What happened, and what you were doing just before:



        (Please don't include names or anything else from a session.)

        Soapcap \(version.text)
        macOS \(macOS)
        Memory \(memoryGB) GB
        Note model \(noteModel)
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

/// Opens a new email in the Mac's mail app.
struct ReportProblemButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Report a Problem…") { openURL(ProblemReport.current.mailURL) }
            .help("Write to \(ProblemReport.address), with this copy's version already filled in")
    }
}

/// The Help menu: this page, and a way to report a problem. Takes the place
/// of the item macOS puts there, which says no help is available.
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            HelpCommand()
            Divider()
            ReportProblemButton()
        }
    }
}

private struct HelpCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Soapcap Help") { openWindow(id: HelpView.window) }.keyboardShortcut("?", modifiers: .command)
    }
}

extension HelpView {
    static let window = "help"
}
