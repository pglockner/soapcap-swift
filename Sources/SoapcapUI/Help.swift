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

/// The window Help › Soapcap Help opens: the sections down a sidebar, and
/// the one chosen beside it, with Report a Problem always at hand.
struct HelpView: View {
    let sections: [HelpPage.Section]
    let isBeta: Bool
    /// The title of the section on show.
    @State private var selection: String?

    /// The sidebar's first item while the app is a beta.
    static let betaTitle = "This is a beta"

    /// Opens on the beta's points while there is a beta, and otherwise on
    /// the first section, unless `showing` names another.
    init(sections: [HelpPage.Section] = HelpPage.sections, isBeta: Bool = Beta.isBeta(AppVersion.current.marketing),
         showing: String? = nil) {
        self.sections = sections
        self.isBeta = isBeta
        _selection = State(initialValue: showing ?? (isBeta ? Self.betaTitle : sections.first?.title))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if isBeta { Text(Self.betaTitle).tag(Self.betaTitle) }
                ForEach(sections) { Text($0.title).tag($0.title) }
            }
            // Wide enough for the longest title, "When something goes wrong".
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ScrollView {
                page
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Each section opens at its top.
            .id(selection)
            .textSelection(.enabled)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    ReportProblemButton()
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.bar)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder private var page: some View {
        if selection == Self.betaTitle {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.betaTitle).font(.title2.weight(.semibold))
                BetaPoints()
            }
        } else if let section = sections.first(where: { $0.title == selection }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.title).font(.title2.weight(.semibold))
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
