import SwiftUI
import IslandCore

/// Play and pause for a background sound, a menu to pick which one, and a volume slider (the system slider, at its
/// normal size: its small sizes lose the larger glass knob).
struct AmbientControls: View {
    @Bindable var player: AmbientPlayer

    private let tint = IslandTheme.ambient

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 32, height: 32)
                        .background(tint, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause the background sound" : "Play a background sound")

                Menu {
                    ForEach(AmbientSound.allCases, id: \.self) { sound in
                        Button { player.select(sound) } label: { Label(sound.title, systemImage: sound.symbol) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: player.sound.symbol)
                        Text(player.sound.title).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tint.opacity(0.18), in: Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose the background sound")
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
                    .tint(tint)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
