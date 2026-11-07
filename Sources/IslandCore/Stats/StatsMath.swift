import Foundation

/// Cumulative CPU time counters, summed over all cores.
public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Cumulative bytes received and sent.
public struct NetCounters: Equatable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public enum StatsMath {
    /// How busy the CPU was between two samples, 0 to 100. Counters that went backwards give 0.
    public static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.user >= previous.user, current.system >= previous.system,
            current.idle >= previous.idle, current.nice >= previous.nice
        else { return 0 }
        let busy = (current.user - previous.user) + (current.system - previous.system) + (current.nice - previous.nice)
        let total = busy + (current.idle - previous.idle)
        guard total > 0 else { return 0 }
        return Double(busy) / Double(total) * 100
    }

    /// Bytes per second in each direction over `interval` seconds. A counter that went backwards (a reset) or an
    /// interval that is not positive gives 0 for that direction.
    public static func networkRate(
        previous: NetCounters, current: NetCounters, interval: TimeInterval
    ) -> (up: Double, down: Double) {
        guard interval > 0 else { return (0, 0) }
        let up = current.bytesOut >= previous.bytesOut ? Double(current.bytesOut - previous.bytesOut) / interval : 0
        let down = current.bytesIn >= previous.bytesIn ? Double(current.bytesIn - previous.bytesIn) / interval : 0
        return (up, down)
    }
}

/// Turns macOS's per-interface byte counters, which are 32-bit and wrap around every 4 GB, into one steadily growing
/// 64-bit total. The first reading of an interface is only a baseline, and a jump of more than half the counter range
/// is taken to be a reset rather than a wrap and counts as nothing.
public struct InterfaceByteAccumulator {
    public private(set) var total: UInt64 = 0
    private var last: [String: UInt32] = [:]

    public init() {}

    public mutating func add(_ readings: [String: UInt32]) {
        for (name, value) in readings {
            if let previous = last[name] {
                let delta = value &- previous  // correct across one wrap of the 32-bit counter
                if delta < 1 << 31 { total += UInt64(delta) }
            }
        }
        last = readings
    }
}

public enum StatsFormat {
    /// "12 KB/s", "2.5 MB/s": decimal units, as network speeds are usually quoted.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        switch value {
        case ..<1_000: return "\(Int(value)) B/s"
        case ..<1_000_000: return String(format: "%.0f KB/s", value / 1_000)
        case ..<1_000_000_000: return String(format: "%.1f MB/s", value / 1_000_000)
        default: return String(format: "%.2f GB/s", value / 1_000_000_000)
        }
    }

    /// Gigabytes of 1024³ bytes, like Activity Monitor.
    public static func memory(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// "128.4 GB free of 494.4 GB": decimal units, as Finder counts disk space.
    public static func storage(_ space: DiskSpace) -> String {
        "\(decimalBytes(space.availableBytes)) free of \(decimalBytes(space.totalBytes))"
    }

    /// "13.6 GB Free": what is left, the top line of the storage pill.
    public static func storageFree(_ space: DiskSpace) -> String {
        "\(decimalBytes(space.availableBytes)) Free"
    }

    /// "232 GB / 245 GB used": the bottom line of the storage pill, in whole units so it stays short.
    public static func storageUsed(_ space: DiskSpace) -> String {
        let used = space.totalBytes - min(space.availableBytes, space.totalBytes)
        return "\(wholeBytes(used)) / \(wholeBytes(space.totalBytes)) used"
    }

    /// An app's memory: whole megabytes below a gigabyte, then gigabytes (1024-based, like `memory`).
    public static func appMemory(_ bytes: UInt64) -> String {
        if bytes < 1_073_741_824 { return String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return memory(bytes)
    }

    /// An app's CPU share, in percent of one core: "41.8%".
    public static func appCPU(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    private static func wholeBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000_000_000: return String(format: "%.0f MB", value / 1_000_000)
        case ..<1_000_000_000_000: return String(format: "%.0f GB", value / 1_000_000_000)
        default: return String(format: "%.2f TB", value / 1_000_000_000_000)
        }
    }

    private static func decimalBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000_000_000: return String(format: "%.0f MB", value / 1_000_000)
        case ..<1_000_000_000_000: return String(format: "%.1f GB", value / 1_000_000_000)
        default: return String(format: "%.2f TB", value / 1_000_000_000_000)
        }
    }
}
