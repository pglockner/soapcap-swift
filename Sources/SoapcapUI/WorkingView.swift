import SoapcapCore
import SwiftUI

/// The screen while something is in progress. While the session's note is
/// drafted it shows the steps the draft goes through, memory, and a way to
/// stop. A test of the model running meanwhile has its own of these, where
/// it was started.
struct WorkingView: View {
    let message: String
    @ObservedObject var run: DraftRun
    @ObservedObject var test: ModelTest
    /// The steps the session's draft has been through, the last still going.
    var steps: [String] = []
    /// How much the model has written in the step in hand, when it says.
    var tokens: Int?
    /// Whether there is an earlier note, which stopping goes back to.
    var keepsEarlierNote = false
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if run.isRunning, !test.isRunning {
                DraftSteps(steps: steps.isEmpty ? [message] : steps, tokens: tokens)
                MemoryCharts(trail: run.trail)
                VStack(spacing: 8) {
                    Button("Stop drafting", action: stop)
                    if keepsEarlierNote {
                        Text("The note you already have is still there until this one is ready. Stop drafting to go back to it.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 8) { WorkingDots(); Text(message) }.font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Something is going on: three dots that light up in turn.
struct WorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "ellipsis")
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous), isActive: !reduceMotion)
            .accessibilityLabel("Working")
    }
}

/// The steps of a draft: those that are over, ticked, and the one going on.
struct DraftSteps: View {
    let steps: [String]
    let tokens: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isGoing = index == steps.count - 1
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if isGoing { WorkingDots() } else { Image(systemName: "checkmark").foregroundStyle(.green) }
                    }
                    .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isGoing ? step : Self.done(step)).foregroundStyle(isGoing ? .primary : .secondary)
                        if isGoing, let tokens {
                            Text(Self.written(tokens)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// A step that is over, without the dots that said it was going on.
    static func done(_ step: String) -> String {
        step.hasSuffix("…") ? String(step.dropLast()) : step
    }

    /// Roughly how much the model has written. It counts in tokens, and
    /// four of those make about three words.
    static func written(_ tokens: Int) -> String {
        let words = tokens * 3 / 4
        return words < 20 ? "a few words so far" : "about \((words + 5) / 10 * 10) words so far"
    }
}

/// Memory in use while a note is drafted, in words: green, yellow from 75%,
/// red from 90%. A test of the model shows it only once it is red.
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
