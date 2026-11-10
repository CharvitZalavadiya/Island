import SwiftUI
import IslandCore

/// The "Updates" part of the Settings window.
struct UpdateSettingsSection: View {
    let update: UpdateController
    let settings: SettingsStore

    var body: some View {
        Section("Updates") {
            LabeledContent("Installed version") {
                Text(verbatim: update.currentVersion.description).monospacedDigit()
            }
            statusRow
            if let release = update.release, update.availableVersion != nil { releaseNotes(release) }
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { settings.settings.checkForUpdates },
                    set: { value in settings.update { $0.checkForUpdates = value } }))
            Text("About once a day Island asks GitHub whether a newer version exists. Nothing about you or your Mac is sent. Installing one downloads it, restarts Island and keeps your settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch update.state {
        case .idle:
            checkButton(label: update.lastChecked.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))" })
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for updates…").foregroundStyle(.secondary) }
        case .upToDate:
            checkButton(label: "Island is up to date.")
        case .available:
            if let version = update.availableVersion {
                HStack {
                    Label("Version \(version.description) is available", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(IslandTheme.accent)
                    Spacer()
                    Button("Install and restart") { Task { await update.installAvailable() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading the new version…")
                ProgressView(value: fraction)
            }
        case .installing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing. Island will restart in a moment.") }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(IslandTheme.keepAwake)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Try again") { Task { if update.release == nil { await update.checkNow() } else { await update.installAvailable() } } }
                    if update.release != nil { Button("See the release page") { update.openReleasePage() } }
                }
            }
        }
    }

    private func checkButton(label: String?) -> some View {
        HStack {
            if let label { Text(label).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button("Check for updates") { Task { await update.checkNow() } }
        }
    }

    private func releaseNotes(_ release: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's new in \(release.version.description)").font(.callout.weight(.semibold))
            ScrollView {
                Text(verbatim: release.whatsNewPlain.isEmpty ? "No notes were published for this release." : release.whatsNewPlain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 110)
            if update.state == .available {
                Button("See the release page") { update.openReleasePage() }.buttonStyle(.link).font(.caption)
            }
        }
    }
}
