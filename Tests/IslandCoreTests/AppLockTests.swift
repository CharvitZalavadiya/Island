import Foundation
import Testing
@testable import IslandCore

// App lock's pure parts: how the password is kept and checked, when a locked app asks again, and the pause after wrong tries.

// MARK: Password

@Test func aPasswordIsKeptAsASaltedHashAndNotAsTheWords() throws {
    let record = try #require(AppLockPassword.makeRecord(for: "tiger-lily", rounds: 10_000))
    #expect(record.isValid)
    #expect(record.hash.count == 32 && record.salt.count == 16)
    let stored = try String(data: JSONEncoder().encode(record), encoding: .utf8) ?? ""
    #expect(!stored.contains("tiger-lily"), "the file must not hold the password itself")
    #expect(AppLockPassword.matches("tiger-lily", record: record))
}

@Test func onlyTheRightPasswordMatches() throws {
    let record = try #require(AppLockPassword.makeRecord(for: "Secret1", rounds: 10_000))
    #expect(!AppLockPassword.matches("secret1", record: record), "capitals count")
    #expect(!AppLockPassword.matches("Secret", record: record))
    #expect(!AppLockPassword.matches("Secret1 ", record: record), "a space at the end is a different password")
    #expect(!AppLockPassword.matches("", record: record))
}

@Test func theSameWordsAreTheSamePasswordHoweverTheAccentIsTyped() throws {
    let composed = "caf\u{00E9}!"                    // é as one character
    let decomposed = "cafe\u{0301}!"                 // e, then an accent
    let record = try #require(AppLockPassword.makeRecord(for: composed, rounds: 10_000))
    #expect(AppLockPassword.matches(decomposed, record: record))
}

@Test func twoRecordsForTheSamePasswordDifferBecauseOfTheirSalt() throws {
    let first = try #require(AppLockPassword.makeRecord(for: "same-words", rounds: 10_000))
    let second = try #require(AppLockPassword.makeRecord(for: "same-words", rounds: 10_000))
    #expect(first.salt != second.salt && first.hash != second.hash)
}

@Test func aDamagedRecordIsNotValidAndNeverMatchesOrFreezesTheIsland() throws {
    let good = try #require(AppLockPassword.makeRecord(for: "abcd", rounds: 10_000))
    var shortHash = good
    shortHash.hash = Data(good.hash.prefix(5))
    var hugeRounds = good
    hugeRounds.rounds = Int.max / 2                  // would take forever if it were tried
    var noSalt = good
    noSalt.salt = Data()
    var newerVersion = good
    newerVersion.version = 2
    for broken in [shortHash, hugeRounds, noSalt, newerVersion] {
        #expect(!broken.isValid)
        let started = Date()
        #expect(!AppLockPassword.matches("abcd", record: broken))
        #expect(Date().timeIntervalSince(started) < 1, "a damaged record must be refused at once, not computed")
    }
}

@Test func theRealRoundCountIsInsideTheRangeTheCheckAccepts() throws {
    #expect(AppLockPassword.roundsRange.contains(AppLockPassword.rounds))
    let record = try #require(AppLockPassword.makeRecord(for: "abcd"))
    #expect(record.rounds == AppLockPassword.rounds && record.isValid)
}

@Test func aNewPasswordNeedsFourCharactersAndTheSameTwice() {
    #expect(AppLockPassword.problem(newPassword: "abc", repeated: "abc") == .tooShort)
    #expect(AppLockPassword.problem(newPassword: "", repeated: "") == .tooShort)
    #expect(AppLockPassword.problem(newPassword: "abcd", repeated: "abce") == .doesNotMatch)
    #expect(AppLockPassword.problem(newPassword: "abcd", repeated: "abcd") == nil)
    #expect(AppLockPassword.problem(newPassword: "😀😀😀😀", repeated: "😀😀😀😀") == nil, "length is in characters, not bytes")
}

// MARK: When a locked app asks again

private let t0 = Date(timeIntervalSince1970: 1_000_000)

/// `#expect` cannot call a mutating method, so the question is asked through this.
private func ask(_ policy: inout AppLockPolicy, _ pid: Int32, _ now: Date) -> Bool { policy.comesToFront(pid: pid, now: now) }

@Test func anAppThatWasNotOpenedYetAsksForThePassword() {
    var policy = AppLockPolicy(relock: .everyTime)
    #expect(ask(&policy, 10, t0))
}

@Test func anAppOpenedWithThePasswordDoesNotAskWhileItIsInUse() {
    var policy = AppLockPolicy(relock: .everyTime)
    policy.opened(pid: 10)
    #expect(!ask(&policy, 10, t0))
    #expect(!ask(&policy, 10, t0.addingTimeInterval(3600)), "still in front, so still in use")
}

@Test func everyTimeAsksAgainAsSoonAsThePersonCameBack() {
    var policy = AppLockPolicy(relock: .everyTime)
    policy.opened(pid: 10)
    policy.leftFront(pid: 10, at: t0)
    #expect(ask(&policy, 10, t0), "even at the same moment")
}

@Test func aTimedChoiceAsksOnlyAfterThatLongAway() {
    var policy = AppLockPolicy(relock: .fiveMinutes)
    policy.opened(pid: 10)
    policy.leftFront(pid: 10, at: t0)
    #expect(!ask(&policy, 10, t0.addingTimeInterval(299)))
    policy.leftFront(pid: 10, at: t0.addingTimeInterval(299))      // away again, counted from now
    #expect(!ask(&policy, 10, t0.addingTimeInterval(299 + 299)))
    policy.leftFront(pid: 10, at: t0)
    #expect(ask(&policy, 10, t0.addingTimeInterval(300)))
}

@Test func afterItAskedAgainItStaysAskingUntilTheyOpenItAgain() {
    var policy = AppLockPolicy(relock: .oneMinute)
    policy.opened(pid: 10)
    policy.leftFront(pid: 10, at: t0)
    #expect(ask(&policy, 10, t0.addingTimeInterval(61)))
    #expect(ask(&policy, 10, t0.addingTimeInterval(62)), "not opened yet, so it asks again")
    policy.opened(pid: 10)
    #expect(!ask(&policy, 10, t0.addingTimeInterval(63)))
}

@Test func aClockThatWentBackwardsAsksInsteadOfStayingOpen() {
    var policy = AppLockPolicy(relock: .fifteenMinutes)
    policy.opened(pid: 10)
    policy.leftFront(pid: 10, at: t0)
    #expect(ask(&policy, 10, t0.addingTimeInterval(-3600)))
}

@Test func onlyAfterTheAppQuitsNeverAsksAgainByTime() {
    var policy = AppLockPolicy(relock: .whenAppQuits)
    policy.opened(pid: 10)
    policy.leftFront(pid: 10, at: t0)
    #expect(!ask(&policy, 10, t0.addingTimeInterval(86_400 * 30)))
    policy.quit(pid: 10)
    #expect(ask(&policy, 10, t0), "a new run of the app is a new app")
}

@Test func leavingAnAppThatWasNeverOpenedStartsNoSession() {
    var policy = AppLockPolicy(relock: .whenAppQuits)
    policy.leftFront(pid: 10, at: t0)
    #expect(ask(&policy, 10, t0), "an app that never got in must not be let in by being left")
}

@Test func forgettingEverythingMakesEveryAppAskAgain() {
    var policy = AppLockPolicy(relock: .whenAppQuits)
    policy.opened(pid: 10)
    policy.opened(pid: 11)
    policy.forgetAll()
    #expect(ask(&policy, 10, t0) && ask(&policy, 11, t0))
}

@Test func eachAppIsKeptTrackOfOnItsOwn() {
    var policy = AppLockPolicy(relock: .everyTime)
    policy.opened(pid: 10)
    #expect(ask(&policy, 11, t0), "another app is not let in because this one was")
    #expect(!ask(&policy, 10, t0))
}

@Test func everyRelockChoiceHasANameAndTheChoicesGrowInTime() {
    let times = AppLockRelock.allCases.compactMap(\.seconds)
    #expect(times == times.sorted() && times.count == AppLockRelock.allCases.count - 1)
    #expect(Set(AppLockRelock.allCases.map(\.title)).count == AppLockRelock.allCases.count)
    #expect(AppLockRelock.whenAppQuits.seconds == nil)
}

// MARK: What cannot be locked

@Test func islandAndTheAppsTheMacNeedsCannotBeLocked() {
    #expect(!AppLockRules.canLock("com.apple.finder", island: "com.example.Island"))
    #expect(!AppLockRules.canLock("com.example.Island", island: "com.example.Island"))
    #expect(!AppLockRules.canLock("", island: nil))
    #expect(AppLockRules.canLock("com.tinyspeck.slackmacgap", island: "com.example.Island"))
}

// MARK: Wrong tries

@Test func fiveWrongTriesAreFreeAndThenThePersonMustWait() {
    var attempts = AppLockAttempts()
    for _ in 0..<(AppLockAttempts.freeTries - 1) {
        attempts.failed(now: t0)
        #expect(attempts.wait(now: t0) == 0)
    }
    attempts.failed(now: t0)
    #expect(attempts.wait(now: t0) == 5)
    #expect(attempts.wait(now: t0.addingTimeInterval(5)) == 0)
}

@Test func theWaitGrowsWithEachFurtherWrongTryButStopsGrowing() {
    var attempts = AppLockAttempts()
    var waits: [TimeInterval] = []
    for _ in 0..<12 {
        attempts.failed(now: t0)
        waits.append(attempts.wait(now: t0))
    }
    #expect(Array(waits[4...8]) == [5, 10, 20, 40, 80])
    #expect(waits.max() == 80, "a wait that kept doubling could keep a person out for good")
}

@Test func aRightPasswordClearsTheWrongTries() {
    var attempts = AppLockAttempts()
    for _ in 0..<7 { attempts.failed(now: t0) }
    attempts.succeeded()
    #expect(attempts.wait(now: t0) == 0)
    attempts.failed(now: t0)
    #expect(attempts.wait(now: t0) == 0, "counting starts again from none")
}

// MARK: Settings

@Test func appLockIsOffAndGuardsNothingUntilTheUserSetsItUp() throws {
    let settings = Settings()
    #expect(!settings.appLockEnabled && settings.appLockApps.isEmpty)
    #expect(settings.appLockRelockChoice == .everyTime && settings.appLockTouchID)
}

@Test func anOldSettingsFileWithoutAppLockKeysKeepsEverythingAndLocksNothing() throws {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    try #"{"focusMinutes": 50, "trackpadEnabled": false}"#.write(to: url, atomically: true, encoding: .utf8)
    let settings = FileStore(url: url, defaultValue: Settings()).load()
    #expect(settings.focusMinutes == 50 && settings.trackpadEnabled == false)
    #expect(!settings.appLockEnabled && settings.appLockApps.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
}

@Test func appLockSettingsRoundTripThroughSaveAndLoad() throws {
    let url = makeTempDirectory().appendingPathComponent("settings.json")
    let store = FileStore(url: url, defaultValue: Settings())
    var settings = Settings()
    settings.appLockEnabled = true
    settings.appLockApps = ["com.example.One", "com.example.Two"]
    settings.appLockNames = ["com.example.One": "One"]
    settings.appLockRelock = AppLockRelock.fiveMinutes.rawValue
    settings.appLockTouchID = false
    try store.save(settings)
    let loaded = store.load()
    #expect(loaded == settings)
    #expect(loaded.appLockRelockChoice == .fiveMinutes)
}

@Test func anUnknownRelockNameAsksEveryTimeWhichIsTheSafeWayRound() {
    var settings = Settings()
    settings.appLockRelock = "someFutureChoice"
    #expect(settings.appLockRelockChoice == .everyTime)
}

// MARK: Which screens the cover goes over

private let screenA = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let screenB = CGRect(x: 1440, y: 0, width: 1440, height: 900)

@Test func theCoverGoesOnlyOverTheScreenTheAppsWindowIsOn() {
    let plan = AppLockCoverage.plan(windows: [CGRect(x: 100, y: 100, width: 800, height: 600)], screens: [screenA, screenB])
    #expect(plan == AppLockCoverPlan(covered: [screenA], card: screenA))
    let other = AppLockCoverage.plan(windows: [CGRect(x: 1700, y: 100, width: 600, height: 400)], screens: [screenA, screenB])
    #expect(other == AppLockCoverPlan(covered: [screenB], card: screenB))
}

@Test func aWindowAcrossTwoScreensCoversBothAndTheBoxGoesWhereMostOfItIs() {
    let across = CGRect(x: 1200, y: 100, width: 700, height: 500)             // 240 wide on A, 460 wide on B
    let plan = AppLockCoverage.plan(windows: [across], screens: [screenA, screenB])
    #expect(plan?.covered == [screenA, screenB] && plan?.card == screenB)
}

@Test func aWindowThatOnlyTouchesTheEdgeOfAScreenDoesNotCountAsBeingOnIt() {
    let plan = AppLockCoverage.plan(windows: [CGRect(x: 1420, y: 100, width: 100, height: 500)], screens: [screenA, screenB])
    #expect(plan?.covered == [screenB], "only 20 points of it reach screen A")
}

@Test func withNoWindowsFoundTheCoverGoesOverEveryScreenWithTheBoxOnTheFirst() {
    #expect(AppLockCoverage.plan(windows: [], screens: [screenA, screenB]) == AppLockCoverPlan(covered: [screenA, screenB], card: screenA))
    let faraway = CGRect(x: 9000, y: 9000, width: 500, height: 500)           // on no screen at all
    #expect(AppLockCoverage.plan(windows: [faraway], screens: [screenA, screenB])?.covered == [screenA, screenB])
}

@Test func withNoScreensThereIsNothingToCover() {
    #expect(AppLockCoverage.plan(windows: [CGRect(x: 0, y: 0, width: 500, height: 500)], screens: []) == nil)
}
