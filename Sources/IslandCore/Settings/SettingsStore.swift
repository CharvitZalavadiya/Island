import Foundation
import Observation

@Observable
public final class SettingsStore {
    public private(set) var settings: Settings
    @ObservationIgnored private let store: FileStore<Settings>

    public init(store: FileStore<Settings>) {
        self.store = store
        self.settings = store.load()
    }

    /// Applies `change` and saves the result immediately.
    public func update(_ change: (inout Settings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
        try? store.save(copy)
    }
}
