import AppKit
import SwiftUI
import IslandCore

/// "Sound" in the Stats tab: the overall volume on top, then one slider for each app that is making sound.
struct AudioMixerSection: View {
    let mixer: AudioMixerController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Sound").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if mixer.anyReduced {
                    PillButton(title: "Reset apps", height: 22) { mixer.resetAll() }
                }
            }

            if let master = mixer.master {
                VolumeRow(
                    icon: .symbol(masterSymbol(master)), name: "Mac", value: master,
                    onChange: { mixer.setMaster($0) })
            } else {
                Text("This sound output has no volume control.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }

            if mixer.apps.isEmpty {
                Text("No app is playing sound right now.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(mixer.apps) { app in
                VolumeRow(
                    icon: .file(app.id), name: app.name, value: mixer.volume(for: app),
                    dimmed: !app.isPlaying, onChange: { mixer.setVolume($0, for: app) })
            }

            if let notice = mixer.notice { NoticeRow(notice: notice, mixer: mixer) }
        }
    }

    private func masterSymbol(_ level: Float) -> String {
        switch level {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct VolumeRow: View {
    enum Icon {
        case symbol(String)
        /// The icon of the app at this path.
        case file(String)
    }

    let icon: Icon
    let name: String
    let value: Float
    var dimmed = false
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 8) {
            iconView.frame(width: 18, height: 18)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 112, alignment: .leading)
            VolumeSlider(value: value, tint: IslandTheme.volume, onChange: onChange)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
        }
        .opacity(dimmed ? 0.55 : 1)
        .help(dimmed ? "\(name) isn't playing right now, but its volume is turned down" : name)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandTheme.volume)
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        }
    }
}

/// A bar you drag along: the same look as the other bars in the Stats tab, with a small handle.
private struct VolumeSlider: View {
    let value: Float
    let tint: Color
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let position = width * CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                Capsule().fill(tint).frame(width: position, height: 6)
                Circle().fill(Color.white).frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .offset(x: min(max(position - 6.5, 0), width - 13))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    onChange(Float(min(max(drag.location.x / width, 0), 1)))
                })
        }
        .frame(height: 22)
    }
}

private struct NoticeRow: View {
    let notice: AudioMixerController.Notice
    let mixer: AudioMixerController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if notice.offersSettings {
                    PillButton(title: "Open Settings", prominent: true, tint: IslandTheme.volume) { mixer.openSettings() }
                }
                PillButton(title: "Dismiss") { mixer.dismissNotice() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandTheme.volume.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
