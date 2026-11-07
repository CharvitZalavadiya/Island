import Observation
import ServiceManagement
import IslandCore

enum LoginItemStatus: Equatable {
    case enabled, notRegistered, requiresApproval, notFound
}

/// Registers Island to open at login. The real one is `SystemLoginItem`; tests use a fake.
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItem: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// The "open at login" switch. The saved setting always matches what macOS really has, so the switch never lies.
@Observable
@MainActor
final class LaunchAtLoginController {
    private(set) var message: String?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let service: LoginItemService

    init(settings: SettingsStore, service: LoginItemService) {
        self.settings = settings
        self.service = service
    }

    var isOn: Bool { settings.settings.launchAtLogin }

    func setOn(_ on: Bool) {
        var failure: String?
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            failure = "Couldn't turn launch at login \(on ? "on" : "off"): \(error.localizedDescription)"
        }

        let enabled = service.status == .enabled
        settings.update { $0.launchAtLogin = enabled }

        if let failure {
            message = failure
        } else if on && !enabled {
            message = service.status == .requiresApproval
                ? "Approve Island in System Settings → General → Login Items to finish turning this on."
                : "macOS didn't turn launch at login on."
        } else {
            message = nil
        }
    }

    /// Adopts what macOS says, for example when the user removed Island from Login Items in System Settings.
    func syncWithSystem() {
        let enabled = service.status == .enabled
        if enabled != settings.settings.launchAtLogin {
            settings.update { $0.launchAtLogin = enabled }
        }
    }
}
