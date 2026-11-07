/// Every mascot Island ships with. To add one, create a file in `Defs/` and list it here.
public enum MascotRegistry {
    public static let all: [MascotDefinition] = [
        .ghost, .cat, .cloud, .flame, .droplet, .cactus,
        .bunny, .bear, .frog, .penguin, .star, .mushroom,
        // The smiling ones, each with a different emotion.
        .sunny, .giggles, .winky, .lovey, .cooly, .blushy,
        .silly, .starry, .dreamy, .zen, .proud, .joyful,
    ]

    /// The mascot with this id, or the ghost if there is none.
    public static func definition(id: String) -> MascotDefinition {
        all.first { $0.id == id } ?? .ghost
    }
}
