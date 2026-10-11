import SoapcapCore
import SwiftUI

/// The screen while something is in progress. While a note is drafted it
/// also shows memory in use and a way to stop.
struct WorkingView: View {
    let message: String
    @ObservedObject var run: DraftRun
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(message)
            if let memory = run.memory { MemoryLine(memory: memory) }
            if run.isRunning { Button("Stop drafting", action: stop).padding(.top, 8) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Memory in use while a note is drafted: green, yellow from 75%, red from 90%.
struct MemoryLine: View {
    let memory: MemoryStatus

    var body: some View {
        Text(memory.summary)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch memory.level {
        case .ok: .green
        case .high: .yellow
        case .critical: .red
        }
    }
}
