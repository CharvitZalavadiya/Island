import Testing
import Foundation
import IslandCore
@testable import IslandUI

private final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    var registerError: Error?
    /// What the status becomes after a successful `register()`.
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var registers = 0
    private(set) var unregisters = 0

    init(_ status: LoginItemStatus) { self.status = status }

    func register() throws {
        registers += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisters += 1
        status = .notRegistered
    }
}

private struct SomeFailure: LocalizedError {
    var errorDescription: String? { "the system said no" }
}

@MainActor
private func makeController(
    _ status: LoginItemStatus, launchAtLogin: Bool = false
) -> (LaunchAtLoginController, SettingsStore, FakeLoginItem) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    let settings = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    settings.update { $0.launchAtLogin = launchAtLogin }
    let service = FakeLoginItem(status)
    return (LaunchAtLoginController(settings: settings, service: service), settings, service)
}

@Test @MainActor func turningItOnRegistersAndRemembersTheChoice() {
    let (controller, settings, service) = makeController(.notRegistered)
    controller.setOn(true)
    #expect(service.registers == 1)
    #expect(settings.settings.launchAtLogin)
    #expect(controller.message == nil)
}

@Test @MainActor func turningItOffUnregisters() {
    let (controller, settings, service) = makeController(.enabled, launchAtLogin: true)
    controller.setOn(false)
    #expect(service.unregisters == 1)
    #expect(!settings.settings.launchAtLogin)
}

@Test @MainActor func aFailedRegistrationLeavesTheSettingOffAndExplainsWhy() {
    let (controller, settings, service) = makeController(.notRegistered)
    service.registerError = SomeFailure()
    controller.setOn(true)
    #expect(!settings.settings.launchAtLogin)
    #expect(controller.message?.contains("the system said no") == true)
}

@Test @MainActor func whenTheSystemWantsApprovalTheSettingStaysOffAndTheMessageSaysWhere() {
    let (controller, settings, service) = makeController(.notRegistered)
    service.statusAfterRegister = .requiresApproval
    controller.setOn(true)
    #expect(!settings.settings.launchAtLogin)
    #expect(controller.message?.contains("Login Items") == true)
}

@Test @MainActor func aSuccessfulChangeClearsAnOldMessage() {
    let (controller, _, service) = makeController(.notRegistered)
    service.registerError = SomeFailure()
    controller.setOn(true)
    #expect(controller.message != nil)
    service.registerError = nil
    controller.setOn(true)
    #expect(controller.message == nil)
}

@Test @MainActor func syncingAdoptsWhatTheSystemSays() {
    let (enabledInSystem, settingsA, _) = makeController(.enabled, launchAtLogin: false)
    enabledInSystem.syncWithSystem()
    #expect(settingsA.settings.launchAtLogin)

    // The user removed Island from Login Items in System Settings.
    let (removedInSystem, settingsB, _) = makeController(.notRegistered, launchAtLogin: true)
    removedInSystem.syncWithSystem()
    #expect(!settingsB.settings.launchAtLogin)
}

@Test @MainActor func syncingWithNothingToChangeTouchesNothing() {
    let (controller, settings, service) = makeController(.enabled, launchAtLogin: true)
    controller.syncWithSystem()
    #expect(settings.settings.launchAtLogin)
    #expect(service.registers == 0 && service.unregisters == 0)
}
