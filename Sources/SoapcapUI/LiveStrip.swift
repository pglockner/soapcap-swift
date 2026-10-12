import SoapcapCapture
import SwiftUI

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
                    Text("\(Text(line.speaker).fontWeight(.medium))  \(line.text)")
                        .foregroundStyle(line.isFinal ? .secondary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.callout)
            .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 96)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}
