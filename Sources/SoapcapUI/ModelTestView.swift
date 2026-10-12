import SoapcapCore
import SoapcapNote
import SwiftUI

/// The button that tries the chosen note model on the sample session, how
/// the try is going, and what came of it.
struct ModelTestView: View {
    @ObservedObject var test: ModelTest
    @ObservedObject private var run: DraftRun
    let model: String
    @State private var showsNote = false

    init(test: ModelTest, model: String) {
        self.test = test
        run = test.run
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .running(let title) = test.state {
                ProgressView { Text(title) }.controlSize(.small)
                if let memory = run.memory, memory.level == .critical { MemoryLine(memory: memory) }
                Button("Stop") { test.stop() }
            } else {
                verdict
                Button("Test \(ModelCatalog.displayName(of: model))") { test.start() }.disabled(!test.canStart)
                Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let advice = ModelCatalog.memoryAdvice(for: model, memory: MemoryStatus.current()) {
                    Text(advice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hint: String {
        test.isBlocked ? "Not while a session is being recorded."
            : "Drafts a note from a made-up session and checks that every section is filled. It takes as long as drafting a note does, and nothing is kept."
    }

    @ViewBuilder private var verdict: some View {
        switch test.state {
        case .good(let model, let seconds):
            Label {
                Text("Good: \(ModelCatalog.displayName(of: model)) drafted a whole note from the sample session in \(seconds) s.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            readNote
        case .problem(let model, let reasons):
            Label {
                Text("Problem: \(ModelCatalog.displayName(of: model)) did not draft a sound note from the sample session.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            ForEach(reasons, id: \.self) { reason in
                Text(reason).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            readNote
        case .idle, .running:
            EmptyView()
        }
    }

    /// The note itself, to judge by eye: a verdict with nothing to look at can't be checked.
    @ViewBuilder private var readNote: some View {
        if let note = test.note {
            Button(showsNote ? "Hide the note" : "Show the note") { showsNote.toggle() }.buttonStyle(.link).font(.callout)
            if showsNote {
                ScrollView {
                    Text(note).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
    }
}
