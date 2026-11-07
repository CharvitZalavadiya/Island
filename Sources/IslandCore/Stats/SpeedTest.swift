import Foundation

/// The outcome of one run of macOS's own `networkQuality` tool.
public struct SpeedTestResult: Equatable {
    public var downloadMegabits: Double
    public var uploadMegabits: Double
    /// Round trips per minute under load (Apple's "responsiveness"): how snappy the connection stays while busy.
    public var responsiveness: Int?
    /// Idle round-trip time in milliseconds.
    public var latencyMilliseconds: Double?

    public init(downloadMegabits: Double, uploadMegabits: Double, responsiveness: Int? = nil, latencyMilliseconds: Double? = nil) {
        self.downloadMegabits = downloadMegabits
        self.uploadMegabits = uploadMegabits
        self.responsiveness = responsiveness
        self.latencyMilliseconds = latencyMilliseconds
    }

    /// "High", "Medium" or "Low", in the spirit of Apple's own wording.
    public var responsivenessLabel: String? {
        guard let responsiveness else { return nil }
        if responsiveness >= 1000 { return "High" }
        if responsiveness >= 300 { return "Medium" }
        return "Low"
    }

    /// Reads the JSON that `networkQuality -c` prints. Nil if it is not a finished test (an error report, or garbage).
    public static func parse(json: Data) -> SpeedTestResult? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let download = (object["dl_throughput"] as? NSNumber)?.doubleValue,
            let upload = (object["ul_throughput"] as? NSNumber)?.doubleValue,
            download.isFinite, upload.isFinite, download >= 0, upload >= 0
        else { return nil }
        return SpeedTestResult(
            downloadMegabits: download / 1_000_000,
            uploadMegabits: upload / 1_000_000,
            responsiveness: (object["responsiveness"] as? NSNumber)?.intValue,
            latencyMilliseconds: (object["base_rtt"] as? NSNumber)?.doubleValue)
    }
}

extension StatsFormat {
    /// "245 Mbps", "8.4 Mbps", "1.20 Gbps".
    public static func megabits(_ value: Double) -> String {
        let value = max(value, 0)
        if value >= 1000 { return String(format: "%.2f Gbps", value / 1000) }
        if value >= 100 { return String(format: "%.0f Mbps", value) }
        return String(format: "%.1f Mbps", value)
    }
}
