import SwiftUI
import IslandCore

/// The Focus tab: the Pomodoro and stopwatch across the whole width, with the background sound beside the buttons.
struct FocusTab: View {
    let services: IslandServices

    var body: some View {
        PomodoroCard(controller: services.pomodoro, ambient: services.ambient)
    }
}

struct PomodoroCard: View {
    @Bindable var controller: PomodoroController
    let ambient: AmbientPlayer

    var body: some View {
        let snapshot = controller.snapshot
        let idle = snapshot.status == .idle
        let mascot = MascotRegistry.definition(id: controller.mascotID)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ModeSwitch(stopwatch: $controller.stopwatchMode)
                    .disabled(!idle)
                    .opacity(idle ? 1 : 0.5)
                Spacer(minLength: 4)
                Text(phaseTitle(snapshot))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // First block: the mascot inside a ring in its own colour that runs out with the time, and the grid of mascots
            // to choose from, which takes all the room to the right end.
            HStack(spacing: 16) {
                RingProgress(fraction: controller.ringFraction, tint: mascot.bodyColor, lineWidth: 5) {
                    BlobMascotView(mascot, mood: controller.mood, size: 52, animated: controller.mascotMoves)
                }
                .frame(width: 92, height: 92)
                MascotGrid(controller: controller)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 98)

            // Second block: the time with + above and − below on its right, the buttons stacked beside it, and the
            // background sound at the far right.
            HStack(spacing: 18) {
                // + and − are only for a countdown that has not started; they keep their space otherwise.
                let adjustable = idle && !controller.stopwatchMode
                HStack(spacing: 10) {
                    Text(timeText(snapshot))
                        .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(snapshot.status == .paused ? .white.opacity(0.5) : .white)
                        .lineLimit(1)
                        .fixedSize()
                    VStack(spacing: 6) {
                        RepeatButton(symbol: "plus") { controller.adjustMinutes(by: 1) }
                        RepeatButton(symbol: "minus") { controller.adjustMinutes(by: -1) }
                    }
                    .opacity(adjustable ? 1 : 0)
                    .allowsHitTesting(adjustable)
                }

                VStack(spacing: 8) {
                    switch snapshot.status {
                    case .idle: SideButton(title: "Start", prominent: true) { controller.start() }
                    case .running: SideButton(title: "Pause", prominent: true) { controller.pause() }
                    case .paused: SideButton(title: "Resume", prominent: true) { controller.resume() }
                    }
                    SideButton(title: "Reset", prominent: false) { controller.reset() }
                }
                .frame(width: 96)

                AmbientControls(player: ambient)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 64)
        }
        .foregroundStyle(.white)
    }

    private func phaseTitle(_ snapshot: PomodoroSnapshot) -> String {
        if snapshot.mode == .stopwatch || (controller.stopwatchMode && snapshot.status == .idle) { return "Stopwatch" }
        switch snapshot.phase {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    private func timeText(_ snapshot: PomodoroSnapshot) -> String {
        if snapshot.mode == .stopwatch { return ClockFormat.stopwatch(snapshot.elapsed) }
        if controller.stopwatchMode && snapshot.status == .idle { return ClockFormat.stopwatch(0) }
        return ClockFormat.countdown(snapshot.remaining)
    }
}

/// A button in the stack beside the time: the label changes (Start, Pause, Resume) but the button's size does not.
private struct SideButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(prominent ? IslandTheme.focus : Color.white.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The "Pomodoro | Stopwatch" switch at the top of the card.
struct ModeSwitch: View {
    @Binding var stopwatch: Bool

    var body: some View {
        HStack(spacing: 2) {
            segment("Pomodoro", selected: !stopwatch) { stopwatch = false }
            segment("Stopwatch", selected: stopwatch) { stopwatch = true }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: Capsule())
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selected ? IslandTheme.focus : Color.clear, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A round − or + button: one press does it once, and holding repeats it (after a short pause) until released.
struct RepeatButton: View {
    let symbol: String
    let action: () -> Void
    @State private var holding: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(IslandTheme.focus)
            .frame(width: 28, height: 28)
            .background(IslandTheme.focus.opacity(0.18), in: Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holding == nil else { return }
                        action()
                        holding = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(nanoseconds: 120_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        holding?.cancel()
                        holding = nil
                    }
            )
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    var tint: Color = IslandTheme.accent
    /// A fixed height (instead of the usual padding), for when the button stands next to something of a set height.
    var height: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, height == nil ? 5 : 0)
                .frame(height: height)
                .background(prominent ? tint : Color.white.opacity(0.14), in: Capsule())
                .foregroundStyle(prominent ? Color.black : Color.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
