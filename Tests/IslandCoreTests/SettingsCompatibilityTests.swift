import Testing
import Foundation
@testable import IslandCore

private func loadSettings(fromJSON json: String) throws -> (Settings, URL) {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    return (FileStore(url: url, defaultValue: Settings()).load(), url)
}

/// What Island v1 wrote: only the keys that existed then.
private let version1File = """
    {"hoverOpens": false, "collapseDelay": 1.2, "mascotID": "frog", "shuffleMascots": true,
     "focusMinutes": 50, "shortBreakMinutes": 10, "longBreakMinutes": 20, "longBreakEvery": 3,
     "autoChain": true, "launchAtLogin": true}
    """

@Test func anOldSettingsFileWithoutNewKeysKeepsTheUsersValues() throws {
    let (settings, url) = try loadSettings(fromJSON: version1File)
    #expect(settings.hoverOpens == false)
    #expect(settings.collapseDelay == 1.2)
    #expect(settings.mascotID == "frog")
    #expect(settings.shuffleMascots == true)
    #expect(settings.focusMinutes == 50)
    #expect(settings.shortBreakMinutes == 10)
    #expect(settings.longBreakMinutes == 20)
    #expect(settings.longBreakEvery == 3)
    #expect(settings.autoChain == true)
    #expect(settings.launchAtLogin == true)
    // The keys that are new in v2 take their defaults.
    #expect(settings.tabOrder == [])
    #expect(settings.cameraMirrored == true)
    // And the file was not treated as corrupt.
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func anEmptyObjectGivesAllDefaults() throws {
    let (settings, _) = try loadSettings(fromJSON: "{}")
    #expect(settings == Settings())
}

@Test func aFileThatIsNotSettingsAtAllStillFallsBackToDefaultsAndKeepsABackup() throws {
    let (settings, url) = try loadSettings(fromJSON: "[1, 2, 3]")
    #expect(settings == Settings())
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
}

@Test func outOfRangeValuesAreClamped() throws {
    let (low, _) = try loadSettings(fromJSON: #"{"focusMinutes": 0, "shortBreakMinutes": -4, "longBreakMinutes": 0, "longBreakEvery": 1, "collapseDelay": 0}"#)
    #expect(low.focusMinutes == 1)
    #expect(low.shortBreakMinutes == 1)
    #expect(low.longBreakMinutes == 1)
    #expect(low.longBreakEvery == 2)
    #expect(low.collapseDelay == 0.1)

    let (high, _) = try loadSettings(fromJSON: #"{"focusMinutes": 999, "shortBreakMinutes": 999, "longBreakMinutes": 999, "longBreakEvery": 99, "collapseDelay": 9}"#)
    #expect(high.focusMinutes == 180)
    #expect(high.shortBreakMinutes == 60)
    #expect(high.longBreakMinutes == 120)
    #expect(high.longBreakEvery == 10)
    #expect(high.collapseDelay == 2)
}

@Test func newFieldsRoundTripThroughSaveAndLoad() throws {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    let store = FileStore(url: url, defaultValue: Settings())
    var settings = Settings()
    settings.tabOrder = ["camera", "focus"]
    settings.cameraMirrored = false
    settings.focusMinutes = 45
    try store.save(settings)
    #expect(store.load() == settings)
}
