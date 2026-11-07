import SwiftUI
import IslandCore

/// The keep-awake panel. Its size never changes: the ring, the button, the checkbox and the note keep their places
/// whatever is pressed or typed, so nothing jumps around under the pointer.
struct KeepAwakeCard: View {
    @Bindable var viewModel: KeepAwakeViewModel

    private let ringSize: CGFloat = 84
    private let tint = IslandTheme.keepAwake

    var body: some View {
        VStack(spacing: 10) {
            Label("Keep awake", systemImage: "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.permission == .missing {
                permissionContent
            } else {
                controls
            }

            // One fixed slot: an error when there is one, otherwise the hint for getting out of a stuck state.
            Group {
                if let message = viewModel.message {
                    Text(message).foregroundStyle(IslandTheme.danger)
                } else {
                    Text("Stuck awake? sudo pmset -a disablesleep 0")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 9))
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    // MARK: Normal use

    private var running: Bool { viewModel.status != .off }

    private var controls: some View {
        VStack(spacing: 12) {
            ring
            WideButton(title: running ? "Stop" : "Start", tint: tint) {
                running ? viewModel.stop() : viewModel.start()
            }
            Button {
                viewModel.isInfinite.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.isInfinite ? "checkmark.square.fill" : "square")
                        .foregroundStyle(viewModel.isInfinite ? tint : .white.opacity(0.6))
                    Text("Awake infinitely").foregroundStyle(.white.opacity(0.8))
                }
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The session that is running keeps its kind; the box can only be changed between sessions.
            .disabled(running)
            .opacity(running ? 0.5 : 1)
        }
    }

    /// The same ring idle and running: the wheel inside it picks the minutes; once running, the time left takes its
    /// place and the ring shrinks like the Pomodoro's. Infinite shows an ∞ and no shrinking.
    private var ring: some View {
        RingProgress(fraction: ringFraction, tint: tint, lineWidth: 6) {
            Group {
                if running {
                    if let remaining = viewModel.remaining {
                        Text(ClockFormat.countdown(remaining))
                            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6)
                    } else {
                        Image(systemName: "infinity").font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                    }
                } else if viewModel.isInfinite {
                    Image(systemName: "infinity").font(.system(size: 26, weight: .semibold)).foregroundStyle(tint.opacity(0.5))
                } else {
                    MinutesWheel(minutes: $viewModel.minutes)
                }
            }
            .frame(width: ringSize - 20, height: ringSize - 20)
            .clipShape(Circle())
        }
        .frame(width: ringSize, height: ringSize)
        .help(running ? "Time left" : "Scroll to pick the minutes")
    }

    /// The ring is full while idle or running without a limit looks the same as "full, nothing to count down".
    private var ringFraction: Double? {
        if running { return viewModel.progress ?? 1 }
        return viewModel.isInfinite ? nil : 1
    }

    // MARK: First-time setup

    /// The one-time setup: what Island needs and why, and the button that makes macOS ask for the password.
    private var permissionContent: some View {
        VStack(spacing: 8) {
            Text("Island needs your OK once to change one power setting, so it can keep your Mac awake. macOS will ask for your password.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            WideButton(title: viewModel.isWorking ? "Waiting…" : "Allow…", tint: tint) {
                Task { await viewModel.grantPermission() }
            }
            .disabled(viewModel.isWorking)
            .opacity(viewModel.isWorking ? 0.6 : 1)
        }
        .frame(height: ringSize + 12 + 26 + 12 + 16)
    }
}

/// A full-width capsule button; its label may change but its size does not.
private struct WideButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(tint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A vertical wheel of the numbers 1 to 60: scroll (mouse wheel or trackpad) to turn it; the number in the middle is
/// the one picked.
struct MinutesWheel: View {
    @Binding var minutes: Int
    @State private var position: Int?

    private let rowHeight: CGFloat = 24

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(KeepAwakeViewModel.minutesRange, id: \.self) { value in
                    Text("\(value)")
                        .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .id(value)
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.3)
                                .scaleEffect(phase.isIdentity ? 1 : 0.78)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, (64 - rowHeight) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .onAppear { position = minutes }
        .onChange(of: position) { _, new in
            if let new { minutes = new }
        }
        .overlay(alignment: .trailing) {
            Text("min").font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.45)).padding(.trailing, 4)
        }
    }
}
