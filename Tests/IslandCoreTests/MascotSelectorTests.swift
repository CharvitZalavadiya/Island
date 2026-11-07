import Testing
@testable import IslandCore

/// A small deterministic generator so the shuffle tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let ids = ["ghost", "cat", "cloud", "flame", "droplet"]

@Test func shuffleNeverRepeatsInARow() {
    var selector = MascotSelector(allIDs: ids, random: SeededGenerator(seed: 42))
    var current = "ghost"
    for _ in 0..<200 {
        let next = selector.nextID(current: current, shuffle: true)
        #expect(next != current)
        #expect(ids.contains(next))
        current = next
    }
}

@Test func shuffleEventuallyVisitsEveryOtherMascot() {
    var selector = MascotSelector(allIDs: ids, random: SeededGenerator(seed: 7))
    var seen: Set<String> = []
    var current = "ghost"
    for _ in 0..<200 {
        current = selector.nextID(current: current, shuffle: true)
        seen.insert(current)
    }
    #expect(seen == Set(ids))
}

@Test func withoutShuffleTheCurrentMascotStays() {
    var selector = MascotSelector(allIDs: ids, random: SeededGenerator(seed: 1))
    #expect(selector.nextID(current: "cloud", shuffle: false) == "cloud")
}

@Test func aSingleMascotAlwaysReturnsItselfEvenWhenShuffling() {
    var selector = MascotSelector(allIDs: ["ghost"], random: SeededGenerator(seed: 1))
    #expect(selector.nextID(current: "ghost", shuffle: true) == "ghost")
}
