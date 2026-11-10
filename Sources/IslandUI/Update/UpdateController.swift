import AppKit
import Foundation
import Observation
import IslandCore

/// Looking for a newer Island, and installing it: the Updates part of Settings.
///
/// - Checking asks GitHub for the newest release (no account, nothing about the person is sent). It happens when asked, and
///   about once a day while Island runs if "Check for updates automatically" is on (it is, until switched off).
/// - Installing downloads the new disk image, checks it, quits Island, swaps the new app in for the old one, and opens it, so
///   nobody has to delete the app and download the disk image again. Settings, logins and bookmarks stay where they are.
@Observable
@MainActor
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The newest release found, if it is newer than this version (kept while it downloads or fails, so it can be tried again).
    private(set) var release: UpdateRelease?
    let currentVersion: AppVersion

    @ObservationIgnored private let feed: UpdateFeed
    @ObservationIgnored private let installer: UpdateInstalling
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let quit: @MainActor () -> Void
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let processID: Int32
    @ObservationIgnored private let relaunchArguments: [String]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var prepared: PreparedUpdate?

    /// How often the automatic check is looked at, and how long it waits between asking GitHub.
    static let automaticInterval: TimeInterval = 20 * 3600
    private static let timerInterval: TimeInterval = 6 * 3600

    init(
        feed: UpdateFeed, installer: UpdateInstalling, settings: SettingsStore, currentVersion: AppVersion,
        now: @escaping () -> Date = { Date() }, quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
        openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }, processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        relaunchArguments: [String] = []
    ) {
        self.feed = feed
        self.installer = installer
        self.settings = settings
        self.currentVersion = currentVersion
        self.now = now
        self.quit = quit
        self.openURL = openURL
        self.processID = processID
        self.relaunchArguments = relaunchArguments
    }

    /// The version of a newer release, if one has been found (the gear menu shows it).
    var availableVersion: AppVersion? {
        guard let release, release.version > currentVersion else { return nil }
        return release.version
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var lastChecked: Date? { settings.settings.lastUpdateCheck }

    // MARK: Checking

    /// "Check for updates": asks GitHub now and says what it found, including a problem.
    func checkNow() async {
        guard !isBusy else { return }
        state = .checking
        do {
            try await look()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// The check that happens by itself: only if it is switched on and one is due, and a failure (no network, say) is not shown.
    func automaticCheckIfDue() async {
        guard settings.settings.checkForUpdates, !isBusy else { return }
        if let last = settings.settings.lastUpdateCheck, now().timeIntervalSince(last) < Self.automaticInterval { return }
        state = .checking
        do {
            try await look()
        } catch {
            state = release == nil ? .idle : .available
        }
    }

    private func look() async throws {
        let latest = try await feed.latestRelease()
        settings.update { $0.lastUpdateCheck = now() }
        if latest.version > currentVersion {
            release = latest
            state = .available
        } else {
            release = nil
            state = .upToDate
        }
    }

    /// Looks for an update a little after launch and then now and then, but only does anything if one is due.
    func startAutomaticChecks(firstDelay: TimeInterval = 30) {
        stopAutomaticChecks()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(firstDelay * 1_000_000_000))
            await self?.automaticCheckIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.timerInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in await self.automaticCheckIfDue() }
        }
        timer?.tolerance = 600
    }

    func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Installing

    /// "Install and restart": downloads and checks the new version, then quits Island so the new one can take its place and open.
    func installAvailable() async {
        guard let release, release.version > currentVersion, !isBusy else { return }
        state = .downloading(0)
        do {
            let ready = try await installer.prepare(release) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            prepared = ready
            state = .installing
            do {
                try installer.relaunch(ready, processID: processID, extraArguments: relaunchArguments)
            } catch {
                installer.discard(ready)
                prepared = nil
                throw error
            }
            quit()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// "See the release page", for when installing in place is not possible.
    func openReleasePage() {
        if let url = release?.pageURL { openURL(url) }
    }

    /// Debug only (`--debug-update-now`): look and install in one go.
    func runDebugUpdateNow() async {
        await checkNow()
        if availableVersion != nil { await installAvailable() }
    }

    private static func message(for error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}
