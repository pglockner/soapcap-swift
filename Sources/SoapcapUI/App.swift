import SoapcapCapture
import SwiftUI

public struct SoapcapApp: App {
    @StateObject private var model = SessionModel()

    public init() {}

    public var body: some Scene {
        WindowGroup("soapcap session") {
            ContentView().environmentObject(model)
                .frame(minWidth: 560, minHeight: 420)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch m.phase {
            case .idle: idle
            case .recording: recording
            case .paused: paused
            case .working(let msg): ProgressView(msg).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .transcript: transcript
            case .note: note
            case .error(let msg): error(msg)
            }
        }
        .padding(16)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to record").font(.title2.bold())
            Text("Use headphones, and turn on Do Not Disturb.").foregroundStyle(.secondary)
            if m.canDeidentify {
                Toggle("De-identify the transcript, and the note once it's drafted", isOn: $m.deidentify)
            }
            HStack {
                Button("Start recording") { m.start() }.keyboardShortcut(.defaultAction)
                Button("Check permissions") { m.diagnose() }
            }
            Spacer()
        }
    }

    private var recording: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack { Circle().fill(.red).frame(width: 12, height: 12)
                Text(String(format: "recording  %02d:%02d", m.elapsed / 60, m.elapsed % 60))
                    .font(.system(.title2, design: .monospaced)) }
            HStack {
                Button("Pause") { m.pause() }
                Button("Stop") { m.stop() }.keyboardShortcut(.defaultAction)
            }
            Spacer()
            LiveStrip(lines: m.liveLines)
        }.frame(maxWidth: .infinity)
    }

    private var paused: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack { Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text(String(format: "paused  %02d:%02d recorded", m.elapsed / 60, m.elapsed % 60))
                    .font(.system(.title2, design: .monospaced)) }
            Text("Nothing is being captured.").foregroundStyle(.secondary)
            HStack {
                Button("Resume") { m.resume() }.keyboardShortcut(.defaultAction)
                Button("Stop") { m.stop() }
            }
            Spacer()
            LiveStrip(lines: m.liveLines).opacity(0.5)
        }.frame(maxWidth: .infinity)
    }

    private func scrollText(_ s: String) -> some View {
        ScrollView { Text(s).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript").font(.headline)
            scrollText(m.transcript)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Picker("Format", selection: $m.format) {
                    ForEach(SessionModel.formats, id: \.self) { Text($0) }
                }.pickerStyle(.segmented).frame(width: 220)
                Button("Draft note") { m.draft() }.keyboardShortcut(.defaultAction)
                Spacer()
                Button("New session") { m.newSession() }
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(m.format.uppercased()) note").font(.headline)
            scrollText(m.note)
            if !m.notice.isEmpty { Text(m.notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(m.copied ? "Copied" : "Keep (copy)") { m.keep() }.keyboardShortcut(.defaultAction)
                Button("Regenerate") { m.draft() }
                Spacer()
                Button("Discard") { m.newSession() }
            }
        }
    }

    private func error(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView { Text(msg).font(.system(.body, design: .monospaced)).foregroundStyle(.orange)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Back") { m.newSession() }
                Button("Check permissions") { m.diagnose() }
            }
        }
    }
}

/// The last few lines heard, to show that both sides are coming through.
/// The full transcript is shown once the session ends.
struct LiveStrip: View {
    let lines: [LiveLine]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if lines.isEmpty {
                    Text("Listening…").foregroundStyle(.tertiary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    (Text(line.speaker + "  ").fontWeight(.medium) + Text(line.text))
                        .foregroundStyle(line.isFinal ? .secondary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.callout)
            .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 96)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

@MainActor private func sampleScreen(_ set: (SessionModel) -> Void) -> some View {
    let m = SessionModel()
    set(m)
    return ContentView().environmentObject(m).frame(width: 560, height: 420)
}

private let previewLines = [
    LiveLine(speaker: "Therapist", text: "How has your sleep been since we last spoke?", isFinal: true),
    LiveLine(speaker: "Client", text: "Better, mostly. The breathing exercises helped the first few nights.", isFinal: true),
    LiveLine(speaker: "Therapist", text: "That's good to hear.", isFinal: true),
    LiveLine(speaker: "Client", text: "Then on Thursday I had the argument with my", isFinal: false),
]

#Preview("Ready") { sampleScreen { _ in } }

#Preview("Recording") {
    sampleScreen { $0.phase = .recording; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Paused") {
    sampleScreen { $0.phase = .paused; $0.elapsed = 754; $0.liveLines = previewLines }
}

#Preview("Transcript") {
    sampleScreen {
        $0.phase = .transcript
        $0.transcript = previewLines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        $0.notice = "transcript: redacted 2 span(s): FIRST_NAME x1, DATE x1"
    }
}
