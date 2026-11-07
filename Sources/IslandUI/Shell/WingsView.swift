import SwiftUI
import IslandCore

/// The collapsed island: a wing on each side of the notch, shown only while something is live.
struct WingsView: View {
    let activities: Set<LiveActivityKind>
    let services: IslandServices

    var body: some View {
        let widths = WingLayout.widths(for: activities)
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LiveActivityKind.allCases.filter { activities.contains($0) && WingLayout.leftWidths[$0] != nil }, id: \.self) { kind in
                    leftContent(for: kind).frame(width: WingLayout.leftWidths[kind])
                }
            }
            .padding(.leading, widths.left > 0 ? WingLayout.edgeInset : 0)
            .frame(width: widths.left, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(LiveActivityKind.allCases.filter { activities.contains($0) && WingLayout.rightWidths[$0] != nil }, id: \.self) { kind in
                    rightContent(for: kind).frame(width: WingLayout.rightWidths[kind])
                }
            }
            .padding(.trailing, widths.right > 0 ? WingLayout.edgeInset : 0)
            .frame(width: widths.right, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func leftContent(for kind: LiveActivityKind) -> some View {
        switch kind {
        case .pomodoro:
            let pomodoro = services.pomodoro
            BlobMascotView(
                MascotRegistry.definition(id: pomodoro.mascotID), mood: pomodoro.mood, size: 22,
                animated: pomodoro.mascotMoves)
        case .keepAwake:
            // The cup sits where the Pomodoro's mascot does, inside a ring that shrinks with the time. A session
            // without a limit has no ring.
            RingProgress(fraction: services.keepAwake.progress, tint: IslandTheme.keepAwake, lineWidth: 2.5) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(IslandTheme.keepAwake)
            }
            .frame(width: 22, height: 22)
        case .focusMode: EmptyView()
        case .media: MediaIconRing(player: services.nowPlaying)
        }
    }

    @ViewBuilder
    private func rightContent(for kind: LiveActivityKind) -> some View {
        switch kind {
        case .pomodoro: pomodoroTime
        case .keepAwake: keepAwakeIndicator
        case .focusMode:
            Image(systemName: "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0xA78BFA))
        case .media: SpectrumBars()
        }
    }

    /// Minutes and seconds left, like the Pomodoro; an infinity sign when there is no limit.
    @ViewBuilder
    private var keepAwakeIndicator: some View {
        if let remaining = services.keepAwake.remaining {
            Text(ClockFormat.countdown(remaining))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Image(systemName: "infinity").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandTheme.keepAwake)
        }
    }

    private var pomodoroTime: some View {
        let pomodoro = services.pomodoro
        let snapshot = pomodoro.snapshot
        let text: String
        if snapshot.status == .idle {
            text = "Done!"
        } else if snapshot.mode == .stopwatch {
            text = ClockFormat.stopwatch(snapshot.elapsed)
        } else {
            text = ClockFormat.countdown(snapshot.remaining)
        }
        return Text(text)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .opacity(snapshot.status == .paused ? 0.5 : 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
