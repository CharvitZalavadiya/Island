import Testing
@testable import IslandCore

private func isInvalid(_ input: MinutesInput) -> Bool {
    if case .invalid = input { return true }
    return false
}

@Test func emptyOrBlankInputMeansIndefinite() {
    #expect(MinutesInput.parse("") == .indefinite)
    #expect(MinutesInput.parse("   ") == .indefinite)
    #expect(MinutesInput.parse("\n") == .indefinite)
}

@Test func wholeMinutesAreAccepted() {
    #expect(MinutesInput.parse("25") == .minutes(25))
    #expect(MinutesInput.parse(" 90 ") == .minutes(90))
    #expect(MinutesInput.parse("1") == .minutes(1))
    #expect(MinutesInput.parse("10080") == .minutes(10080))
}

@Test func everythingElseIsInvalidAndNeverIndefinite() {
    let bad = ["0", "-5", "abc", "1.5", "99999999999", "99999999999999999999", "10081", "12a", "+5", "1 2", "٣"]
    for text in bad {
        #expect(isInvalid(MinutesInput.parse(text)), "\(text) should be invalid")
    }
}

@Test func invalidInputCarriesAMessageForTheUser() {
    guard case .invalid(let message) = MinutesInput.parse("abc") else {
        Issue.record("expected .invalid")
        return
    }
    #expect(!message.isEmpty)
}
