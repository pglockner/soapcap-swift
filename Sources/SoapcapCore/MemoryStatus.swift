import Darwin
import Foundation

/// How full this Mac's memory is, measured the way Activity Monitor's
/// memory pressure is.
public struct MemoryStatus: Equatable, Sendable {
    public enum Level: Equatable, Sendable { case ok, high, critical }

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

    /// Memory in use as a percentage of RAM, counting swap, so it passes 100
    /// once the Mac is swapping to make room, which slows a model a lot.
    public var usedPercent: Int {
        100 - freePercent + (totalBytes == 0 ? 0 : Int(swapUsedBytes * 100 / totalBytes))
    }

    public var level: Level { usedPercent >= 90 ? .critical : usedPercent >= 75 ? .high : .ok }

    public var totalGB: Double { Double(totalBytes) / Self.gigabyte }
    public var availableGB: Double { totalGB * Double(freePercent) / 100 }

    /// "Memory 82%"; from 90% it adds the swap in use, which is what pushes
    /// the figure up: "Memory 104%, swap 42% (2.1 GB)".
    public var summary: String {
        var text = "Memory \(usedPercent)%"
        if level == .critical, swapTotalBytes > 0 {
            text += String(format: ", swap %d%% (%.1f GB)", Int(swapUsedBytes * 100 / swapTotalBytes), Double(swapUsedBytes) / Self.gigabyte)
        }
        return text
    }

    /// What to tell someone about to load a model that takes `needGB`, or
    /// nil when there is room for it with a gigabyte to spare.
    public func advice(beforeLoading model: String, needGB: Double) -> String? {
        if totalGB < needGB * 1.5 {
            return String(format: "%@ takes about %.0f GB and this Mac has %.0f GB of memory. Expect drafting to be very slow.", model, needGB, totalGB)
        }
        guard availableGB < needGB + 1 else { return nil }
        return String(format: "About %.0f GB of memory is free and %@ takes about %.0f GB. Close other apps before drafting, or it will be slow.",
                      availableGB.rounded(.down), model, needGB)
    }

    /// Swap in use from which making more room gets slow. Below it macOS
    /// frees memory for a model without much trouble.
    public static let heavySwapGB = 6.0

    public var swapUsedGB: Double { Double(swapUsedBytes) / Self.gigabyte }

    /// What to ask before loading a model that takes `needGB`, or nil. Only
    /// when the model is two gigabytes or more short of fitting and swap is
    /// already heavily used.
    public func question(beforeLoading model: String, needGB: Double) -> String? {
        guard availableGB <= needGB - 2, swapUsedGB >= Self.heavySwapGB else { return nil }
        return String(format: "About %.0f GB of memory is free and %.0f GB is already in swap. %@ takes about %.0f GB. Drafting now will be very slow and may slow the whole Mac. Close other apps first, or choose a lighter model in Settings.",
                      availableGB.rounded(.down), swapUsedGB.rounded(.down), model, needGB)
    }

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
