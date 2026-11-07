import Testing
import Foundation
@testable import IslandCore

@Test func settingsDefaultsMatchTheSpec() {
    let s = Settings()
    #expect(s.hoverOpens == true)
    #expect(s.collapseDelay == 0.4)
    #expect(s.mascotID == "ghost")
    #expect(s.shuffleMascots == false)
    #expect(s.focusMinutes == 25)
    #expect(s.shortBreakMinutes == 5)
    #expect(s.longBreakMinutes == 15)
    #expect(s.longBreakEvery == 4)
    #expect(s.autoChain == false)
    #expect(s.launchAtLogin == false)
}

@Test func settingsUpdatePersists() {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    let first = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    first.update { $0.focusMinutes = 50 }
    #expect(first.settings.focusMinutes == 50)

    let second = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    #expect(second.settings.focusMinutes == 50)
}

@Test func corruptSettingsFileStartsWithDefaults() throws {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    try "garbage".write(to: url, atomically: true, encoding: .utf8)
    let store = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    #expect(store.settings == Settings())
}
