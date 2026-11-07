/// Picks which mascot to show for the next session.
public struct MascotSelector<Generator: RandomNumberGenerator> {
    private let allIDs: [String]
    private var random: Generator

    public init(allIDs: [String], random: Generator) {
        self.allIDs = allIDs
        self.random = random
    }

    /// With `shuffle` off the current mascot stays. With it on, any other mascot is chosen,
    /// so the same one never shows twice in a row (unless there is only one).
    public mutating func nextID(current: String, shuffle: Bool) -> String {
        guard shuffle else { return current }
        let candidates = allIDs.filter { $0 != current }
        return candidates.randomElement(using: &random) ?? current
    }
}
