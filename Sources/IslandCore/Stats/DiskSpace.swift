import Foundation

/// How much room a volume has, the way Finder and System Settings count it: space the system could free up
/// (purgeable caches, local snapshots) is counted as available.
public struct DiskSpace: Equatable {
    public var availableBytes: UInt64
    public var totalBytes: UInt64

    public init(availableBytes: UInt64, totalBytes: UInt64) {
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    /// The share that is taken, 0 to 1.
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - min(availableBytes, totalBytes)) / Double(totalBytes)
    }

    /// The volume that holds `url`, or nil if it cannot be read.
    public static func read(at url: URL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        let totalBytes = UInt64(total)
        return DiskSpace(availableBytes: min(UInt64(max(available, 0)), totalBytes), totalBytes: totalBytes)
    }
}
