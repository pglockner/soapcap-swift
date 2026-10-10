import SoapcapCore
import SwiftUI

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
