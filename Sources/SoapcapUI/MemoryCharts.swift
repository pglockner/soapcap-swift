import Charts
import SoapcapCore
import SwiftUI

/// Memory, and what has spilled over to disk, while a note is drafted: the
/// last few minutes, newest at the right, the way Activity Monitor draws
/// memory pressure. A model that outgrows memory slows to a crawl, and this
/// is where that shows.
struct MemoryCharts: View {
    let trail: [MemoryStatus]

    var body: some View {
        HStack(spacing: 14) {
            MemoryChart(title: "Memory", value: trail.last.map { "\(100 - $0.freePercent)%" } ?? "",
                        points: trail.map { Double(100 - $0.freePercent) / 100 }, tint: Self.tint(trail.last?.level ?? .ok))
            MemoryChart(title: "Swap (disk)", value: trail.last.map(Self.swapText) ?? "",
                        points: trail.map { min($0.swapUsedGB / Self.swapScaleGB, 1) }, tint: Self.swapTint(trail.last?.swapUsedGB ?? 0))
        }
    }

    /// What fills the swap chart to the top: a third more than the amount
    /// the app already treats as heavy.
    static let swapScaleGB = MemoryStatus.heavySwapGB * 4 / 3

    static func tint(_ level: MemoryStatus.Level) -> Color {
        switch level {
        case .ok: .green
        case .high: .yellow
        case .critical: .red
        }
    }

    static func swapTint(_ gigabytes: Double) -> Color {
        gigabytes >= MemoryStatus.heavySwapGB ? .red : gigabytes >= MemoryStatus.heavySwapGB / 2 ? .yellow : .green
    }

    static func swapText(_ memory: MemoryStatus) -> String {
        memory.swapUsedGB < 0.05 ? "none" : String(format: "%.1f GB", memory.swapUsedGB)
    }
}

private struct MemoryChart: View {
    let title: String
    let value: String
    /// Readings from 0 to 1, oldest first.
    let points: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
            Chart(Array(points.enumerated()), id: \.offset) { index, point in
                // The newest reading sits at the right-hand edge.
                let x = index + DraftRun.trailLength - points.count
                AreaMark(x: .value("Reading", x), y: .value(title, point)).foregroundStyle(tint.opacity(0.3))
                LineMark(x: .value("Reading", x), y: .value(title, point)).foregroundStyle(tint)
            }
            .chartXScale(domain: 0...(DraftRun.trailLength - 1))
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 44)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(width: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
