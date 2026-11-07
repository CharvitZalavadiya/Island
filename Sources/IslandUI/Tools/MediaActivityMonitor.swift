import Foundation
import Observation
import IslandCore

/// Puts the media activity on the minimal view while something is playing, if the setting allows it.
///
/// It is the reason the player's helper runs when the Tools tab is closed, so it only asks for the helper while the
/// setting is on. A short pause between two songs (the system reports "nothing playing" for a moment) does not make the
/// wings blink away: the activity is removed only after `grace` seconds without anything playing.
@MainActor
final class MediaActivityMonitor {
    private let player: NowPlayingController
    private let model: IslandModel
    private let grace: TimeInterval
    private var removal: Task<Void, Never>?
    /// Whether this monitor put the activity there (it never removes one it did not add, such as `--debug-wings`).
    private var showing = false
    private var started = false

    init(player: NowPlayingController, model: IslandModel, grace: TimeInterval = 3) {
        self.player = player
        self.model = model
        self.grace = grace
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    /// Looks at the setting and at what is playing, and sets itself up to look again whenever either changes.
    private func refresh() {
        let (enabled, playing) = withObservationTracking {
            (model.settings.settings.mediaInMinimalView, player.isAvailable && player.track?.isPlaying == true)
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        apply(enabled: enabled, playing: playing)
    }

    private func apply(enabled: Bool, playing: Bool) {
        if enabled { player.start(for: .minimalView) } else { player.stop(for: .minimalView) }

        if enabled && playing {
            removal?.cancel()
            removal = nil
            showing = true
            model.setActivity(.media, active: true)
        } else if showing {
            if !enabled {
                remove()
            } else if removal == nil {
                // Not playing right now: wait a moment before taking it away, in case it starts again.
                removal = Task { [weak self, grace] in
                    try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    self.removal = nil
                    if !(self.player.isAvailable && self.player.track?.isPlaying == true) { self.remove() }
                }
            }
        }
    }

    private func remove() {
        removal?.cancel()
        removal = nil
        showing = false
        model.setActivity(.media, active: false)
    }
}
