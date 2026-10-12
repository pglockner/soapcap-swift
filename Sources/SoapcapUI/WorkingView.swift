import SoapcapCore
import SwiftUI

/// The screen while something is in progress. While the session's note is
/// drafted it also shows memory in use and a way to stop. A test of the
/// model running meanwhile has its own of both, where it was started.
struct WorkingView: View {
    let message: String
    @ObservedObject var run: DraftRun
    @ObservedObject var test: ModelTest
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(message)
            if !test.isRunning {
                if let memory = run.memory { MemoryLine(memory: memory) }
                if run.isRunning { Button("Stop drafting", action: stop).padding(.top, 8) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Memory in use while a note is drafted: green, yellow from 75%, red from 90%.
struct MemoryLine: View {
    let memory: MemoryStatus

    var body: some View {
        Text(memory.summary)
            .font(.caption).monospacedDigit()
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
