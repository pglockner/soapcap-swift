import SwiftUI

/// What went wrong, with the way back and the checks.
struct ErrorScreen: View {
    @EnvironmentObject var m: SessionModel
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Label { Text(message).textSelection(.enabled) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Back") { m.back() }
                Button("Check permissions") { m.diagnose() }
            }
        }
    }
}
