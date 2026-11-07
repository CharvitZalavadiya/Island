import AppKit
import SwiftUI
import IslandCore

/// The player on the Tools tab: a tall tile with what is playing, a progress bar you can click or drag to move around
/// in the track, and the previous / play-pause / next keys.
struct PlayerTile: View {
    let controller: NowPlayingController
    let width: CGFloat
    let height: CGFloat

    /// How far the skip buttons jump when the playing app has no previous or next track (a single video, a podcast).
    private static let skipSeconds: TimeInterval = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .unavailable(let message) = controller.status {
                unavailable(message)
            } else if let track = controller.track {
                playing(track)
            } else {
                idle
            }
        }
        .padding(12)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(IslandTheme.tools.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
    }

    // MARK: States

    private func playing(_ track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let icon = controller.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandTheme.tools)
                }
                Text(controller.sourceName ?? "Now playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Text(track.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            if let artist = track.artist {
                Text(artist)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .padding(.top, 3)
            }
            Spacer(minLength: 8)
            SeekBar(track: track, tint: IslandTheme.tools) { controller.seek(to: $0) }
            controls(track)
                .padding(.top, 10)
        }
    }

    private var idle: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(IslandTheme.tools.opacity(0.8))
            Text(controller.status == .starting ? "Looking…" : "Nothing playing")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 8)
            Text("Play music or a video and it shows up here.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.top, 3)
            Spacer(minLength: 8)
            idleControls
        }
        .frame(maxWidth: .infinity)
    }

    private func unavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IslandTheme.keepAwake)
            Text("Player unavailable").font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Keys

    /// Previous, play/pause and next. When the playing app has no previous or next track the two side keys become
    /// "back 10 seconds" and "forward 10 seconds", which almost every player allows.
    private func controls(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 14) {
            if track.canPrevious {
                keyButton("backward.fill", help: "Previous track") { controller.send(.previousTrack) }
            } else {
                keyButton("gobackward.10", help: "Back 10 seconds", enabled: track.isSeekable) { controller.skip(by: -Self.skipSeconds) }
            }
            playPause(isPlaying: track.isPlaying)
            if track.canNext {
                keyButton("forward.fill", help: "Next track") { controller.send(.nextTrack) }
            } else {
                keyButton("goforward.10", help: "Forward 10 seconds", enabled: track.isSeekable) { controller.skip(by: Self.skipSeconds) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var idleControls: some View {
        HStack(spacing: 14) {
            keyButton("backward.fill", help: "Previous track", enabled: false) {}
            playPause(isPlaying: false, enabled: false)
            keyButton("forward.fill", help: "Next track", enabled: false) {}
        }
        .frame(maxWidth: .infinity)
    }

    private func playPause(isPlaying: Bool, enabled: Bool = true) -> some View {
        Button { controller.send(.togglePlayPause) } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(isPlaying ? "Pause" : "Play")
    }

    private func keyButton(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(help)
    }
}

/// The progress bar with the two times under it: how long it has played, and how long it is. Click or drag on the bar to
/// move to that point (when the app allows it). While playing it moves once a second.
struct SeekBar: View {
    let track: NowPlayingTrack
    let tint: Color
    let onSeek: (TimeInterval) -> Void

    /// Where the pointer is on the bar (0 to 1) while it is pressed.
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let played = track.fraction(at: context.date) ?? 0
            let shown = scrub ?? played
            VStack(spacing: 2) {
                GeometryReader { geometry in
                    let width = max(geometry.size.width, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 5)
                        Capsule().fill(tint).frame(width: width * shown, height: 5)
                        if track.isSeekable, hovering || scrub != nil {
                            Circle().fill(Color.white).frame(width: 11, height: 11)
                                .offset(x: min(max(width * shown - 5.5, 0), width - 11))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard track.isSeekable else { return }
                                scrub = min(max(drag.location.x / width, 0), 1)
                            }
                            .onEnded { drag in
                                guard track.isSeekable, let duration = track.duration else { scrub = nil; return }
                                let fraction = min(max(drag.location.x / width, 0), 1)
                                onSeek(fraction * duration)
                                scrub = nil
                            })
                    .onHover { hovering = $0 }
                }
                .frame(height: 18)
                HStack {
                    Text(NowPlayingFormat.clock(elapsedShown(at: context.date)))
                    Spacer()
                    Text(track.duration.map(NowPlayingFormat.clock) ?? "Live")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .help(track.isSeekable ? "Click or drag to move to that point" : "")
    }

    private func elapsedShown(at date: Date) -> TimeInterval {
        if let scrub, let duration = track.duration { return scrub * duration }
        return track.elapsed(at: date)
    }
}
