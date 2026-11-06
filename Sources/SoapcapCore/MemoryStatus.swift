import Darwin
import Foundation

/// How full this Mac's memory is, measured the way Activity Monitor's
/// memory pressure is.
public struct MemoryStatus: Equatable, Sendable {
    public var totalBytes: UInt64
    /// The system's own figure for memory still available, as a percentage.
    public var freePercent: Int
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64

    public init(totalBytes: UInt64, freePercent: Int, swapUsedBytes: UInt64 = 0, swapTotalBytes: UInt64 = 0) {
        self.totalBytes = totalBytes
        self.freePercent = freePercent
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }

    private static let gigabyte = 1_073_741_824.0

    public var totalGB: Double { Double(totalBytes) / Self.gigabyte }
    public var availableGB: Double { totalGB * Double(freePercent) / 100 }

    /// A quiet note for a Mac with too little memory for `model` to stay in
    /// it beside macOS, or nil. Only the Mac's total memory counts, not what
    /// is free. Measured on a 16 GB Mac (2026-11-05): no model drafted more
    /// than about a quarter slower with other programs holding up to 14 GB,
    /// idle or busy, and 12 GB in swap; and `freePercent` read 87% with
    /// another program holding 10 GB, so it can't say what is free. Not
    /// measured on a Mac with less memory.
    public func advice(beforeLoading model: String, needGB: Double) -> String? {
        guard totalGB < needGB * 1.5 else { return nil }
        return String(format: "%@ takes about %.0f GB and this Mac has %.0f GB of memory, so drafting may take longer.", model, needGB, totalGB)
    }

    /// Swap the memory charts show as heavy. A draft went on at its usual
    /// pace with twice this in swap (see `advice`); it marks where swap is
    /// worth a look, not where drafting slows.
    public static let heavySwapGB = 6.0

    public var swapUsedGB: Double { Double(swapUsedBytes) / Self.gigabyte }

    /// Reads the current figures; nil if the system won't say.
    public static func current() -> MemoryStatus? {
        var level: Int32 = 0, levelSize = MemoryLayout<Int32>.size
        var total: UInt64 = 0, totalSize = MemoryLayout<UInt64>.size
        var swap = xsw_usage(), swapSize = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &levelSize, nil, 0) == 0,
              sysctlbyname("hw.memsize", &total, &totalSize, nil, 0) == 0, total > 0 else { return nil }
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) != 0 { swap = xsw_usage() }
        return MemoryStatus(totalBytes: total, freePercent: Int(level), swapUsedBytes: swap.xsu_used, swapTotalBytes: swap.xsu_total)
    }
}
