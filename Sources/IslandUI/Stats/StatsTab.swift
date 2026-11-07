import SwiftUI
import IslandCore

struct StatsTab: View {
    let sampler: StatsSampler
    let mixer: AudioMixerController

    var body: some View {
        ScrollView { StatsContent(sampler: sampler, mixer: mixer) }
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
            // Samples only while this tab is on screen: leaving the tab or collapsing the island removes it.
            .onAppear { sampler.start(); mixer.start() }
            .onDisappear { sampler.stop(); mixer.stop() }
    }
}

/// The readings themselves, separate from the scrolling so they can be laid out and checked on their own.
struct StatsContent: View {
    let sampler: StatsSampler
    let mixer: AudioMixerController

    var body: some View {
        let memoryFraction = sampler.memoryTotalBytes > 0
            ? Double(sampler.memoryUsedBytes) / Double(sampler.memoryTotalBytes) : 0
        VStack(spacing: 12) {
            StatRow(
                title: "CPU", value: String(format: "%.0f%%", sampler.cpuPercent),
                fraction: sampler.cpuPercent / 100, tint: IslandTheme.statCPU,
                isOpen: sampler.expanded.contains(.cpu), onTap: { sampler.toggle(.cpu) })
            if sampler.expanded.contains(.cpu) { TopApps(sampler: sampler, metric: .cpu) }

            StatRow(
                title: "Memory",
                value: "\(StatsFormat.memory(sampler.memoryUsedBytes)) of \(StatsFormat.memory(sampler.memoryTotalBytes))",
                fraction: memoryFraction, tint: IslandTheme.statMemory,
                isOpen: sampler.expanded.contains(.memory), onTap: { sampler.toggle(.memory) })
            if sampler.expanded.contains(.memory) { TopApps(sampler: sampler, metric: .memory) }

            // Download and upload on the left, taking whatever room is left. The speed test button (only as wide as its
            // label) and the storage pill (35 % of the row) are pushed to the right edge.
            GeometryReader { geometry in
                HStack(spacing: 10) {
                    NetworkReading(symbol: "arrow.down", label: "Download", rate: sampler.downBytesPerSec, tint: IslandTheme.download)
                    NetworkReading(symbol: "arrow.up", label: "Upload", rate: sampler.upBytesPerSec, tint: IslandTheme.upload)
                    Spacer(minLength: 0)
                    SpeedTestButton(sampler: sampler)
                    if let disk = sampler.disk {
                        StoragePill(disk: disk).frame(width: geometry.size.width * 0.35)
                    }
                }
            }
            .frame(height: StoragePill.height)
            SpeedTestResultLine(state: sampler.speedTest, onClose: { sampler.dismissSpeedTest() })

            AudioMixerSection(mixer: mixer)
        }
    }
}

/// A labelled bar. With `onTap` it is a button that opens a dropdown below it, and shows a chevron.
private struct StatRow: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color
    var isOpen = false
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .help("Show which apps use the most \(title.lowercased())")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                Spacer()
                Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 8)
        }
        .contentShape(Rectangle())
    }
}

/// The apps using the most CPU or memory, while a dropdown is open. CPU is each app's share of the whole Mac, so the
/// shares add up to (about) the figure in the row above.
private struct TopApps: View {
    let sampler: StatsSampler
    let metric: Metric

    var body: some View {
        let apps = sampler.topApps(for: metric)
        let tint = metric == .cpu ? IslandTheme.statCPU : IslandTheme.statMemory
        VStack(spacing: 5) {
            if apps.isEmpty {
                Text(sampler.appsLoaded ? "Couldn't read the list of apps." : "Reading…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(apps) { app in
                    HStack {
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(metric == .cpu ? StatsFormat.appCPU(sampler.cpuShare(of: app)) : StatsFormat.appMemory(app.residentBytes))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                Text(metric == .cpu ? "Each app's share of the whole CPU." : "Approximate: memory shared between an app's processes is counted in each.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NetworkReading: View {
    let symbol: String
    let label: String
    let rate: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 14, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(StatsFormat.rate(rate))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(height: StoragePill.height)
    }
}

/// How much room is left on the disk, in a pill like a running track: what is free on top, how much of the whole is used
/// below, a border all around, and the used part of the lane tinted from green through orange to red. It is as tall as
/// the download and upload readings beside it.
private struct StoragePill: View {
    static let height: CGFloat = 36
    let disk: DiskSpace

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [IslandTheme.storageLow, IslandTheme.storageMid, IslandTheme.storageHigh],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width)
                    .opacity(0.4)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geometry.size.width * min(max(disk.usedFraction, 0), 1))
                    }
            }
            VStack(spacing: 1) {
                Text(StatsFormat.storageFree(disk))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                Text(StatsFormat.storageUsed(disk))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
        }
        .frame(height: Self.height)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        .help("How much disk space is left, and how much of the disk is used")
    }
}

/// The button that runs the internet speed test. It is as wide as its longer label needs (both labels are laid out, one
/// of them invisible), so it keeps its size while testing.
private struct SpeedTestButton: View {
    let sampler: StatsSampler

    var body: some View {
        let running = sampler.speedTest == .running
        Button {
            sampler.startSpeedTest()
        } label: {
            ZStack {
                label(running: false).opacity(running ? 0 : 1)
                label(running: true).opacity(running ? 1 : 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(IslandTheme.speedTest.opacity(0.2), in: Capsule())
            .foregroundStyle(IslandTheme.speedTest)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(running)
        .fixedSize()
        .help("Measure your internet speed with macOS's own network test (takes about 20 seconds)")
    }

    private func label(running: Bool) -> some View {
        HStack(spacing: 5) {
            if running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "speedometer")
            }
            Text(running ? "Testing…" : "Speed test")
        }
    }
}

/// What the last speed test found, under the network row. A finished or failed result has a close button at the far
/// right that removes the bar.
private struct SpeedTestResultLine: View {
    let state: SpeedTestState
    let onClose: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            line(closable: false) {
                Text("Measuring… this takes about 20 seconds.").foregroundStyle(.white.opacity(0.6))
            }
        case .finished(let result):
            line(closable: true) {
                HStack(spacing: 12) {
                    Label(StatsFormat.megabits(result.downloadMegabits), systemImage: "arrow.down")
                        .foregroundStyle(IslandTheme.download)
                    Label(StatsFormat.megabits(result.uploadMegabits), systemImage: "arrow.up")
                        .foregroundStyle(IslandTheme.upload)
                    if let label = result.responsivenessLabel {
                        Text("Responsiveness \(label)").foregroundStyle(.white.opacity(0.6))
                    }
                    if let latency = result.latencyMilliseconds {
                        Text(String(format: "%.0f ms", latency)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        case .failed(let message):
            line(closable: true) { Text(message).foregroundStyle(IslandTheme.danger) }
        }
    }

    private func line<Content: View>(closable: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if closable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, closable ? 7 : 10)
        .padding(.vertical, 6)
        .background(IslandTheme.speedTest.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
