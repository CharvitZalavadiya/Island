import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor
private func makeModel() -> IslandModel {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    return IslandModel(settings: SettingsStore(store: FileStore(url: url, defaultValue: Settings())))
}

@Test @MainActor func aFocusModeBeingOnLightsTheMoonAndOffClearsIt() {
    let model = makeModel()
    var reading: Bool? = true
    let monitor = FocusStatusMonitor(model: model, readStatus: { reading })

    monitor.poll()
    #expect(monitor.isFocused)
    #expect(model.activities.contains(.focusMode))

    reading = false
    monitor.poll()
    #expect(!monitor.isFocused)
    #expect(!model.activities.contains(.focusMode))
}

@Test @MainActor func anUnknownFocusStatusCountsAsNotFocused() {
    let model = makeModel()
    let monitor = FocusStatusMonitor(model: model, readStatus: { nil })
    monitor.poll()
    #expect(!monitor.isFocused)
    #expect(!model.activities.contains(.focusMode))
}
