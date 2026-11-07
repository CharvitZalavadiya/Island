import Foundation
import Intents
import Observation

/// Shows a moon in the collapsed pill while a macOS Focus mode is on.
/// macOS only says whether a Focus is on, not which one, and only after a one-time permission.
/// If permission is denied the status stays unknown and the indicator simply stays hidden.
@Observable
@MainActor
public final class FocusStatusMonitor {
    public private(set) var isFocused = false

    @ObservationIgnored private let model: IslandModel
    @ObservationIgnored private let readStatus: () -> Bool?
    @ObservationIgnored private var timer: Timer?

    public init(model: IslandModel, readStatus: @escaping () -> Bool? = FocusStatusMonitor.systemStatus) {
        self.model = model
        self.readStatus = readStatus
    }

    /// Asks for permission once, then watches the Focus status.
    public func requestAndStart() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.startPolling() }
        }
    }

    /// Reads the status now. A missing reading counts as "not focused".
    public func poll() {
        isFocused = readStatus() ?? false
        model.setActivity(.focusMode, active: isFocused)
    }

    private func startPolling() {
        poll()
        guard timer == nil else { return }
        // macOS offers no change notification for Focus, so check every few seconds.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated public static func systemStatus() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }
}
