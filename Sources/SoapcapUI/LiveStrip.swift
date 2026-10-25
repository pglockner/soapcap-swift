import SoapcapCapture
import SwiftUI

/// The last few lines heard, to show that both sides are coming through.
/// The full transcript is shown once the session ends.
struct LiveStrip: View {
    /// The room it takes at the foot of the window.
    static let height: CGFloat = 96

    let lines: [LiveLine]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if lines.isEmpty {
                    Text("Listening…").foregroundStyle(.secondary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text("\(Text(line.speaker).fontWeight(.medium))  \(line.text)")
                        // Heard lines at full strength, ones still being heard
                        // a step back; tertiary was too faint to read.
                        .foregroundStyle(line.isFinal ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.callout)
            .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: Self.height)
        .readingBox()
    }
}
