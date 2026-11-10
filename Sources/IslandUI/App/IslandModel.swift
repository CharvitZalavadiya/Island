import Foundation
import SwiftUI
import Observation
import IslandCore

public enum IslandTab: String, CaseIterable, Hashable {
    case focus, awake, clipboard, shelf, stats, camera, calendar, tasks, base64, tools, github, teams, browser

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .stats: "Stats"
        case .camera: "Camera"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .awake: "Awake"
        case .base64: "Base64 & Cron"
        case .tools: "Tools"
        case .github: "GitHub"
        case .teams: "Teams"
        case .browser: "Browser"
        }
    }

    /// The colour each tab wears in the tab bar when it is the one open.
    var color: Color {
        switch self {
        case .focus: IslandTheme.focus
        case .clipboard: IslandTheme.clipboard
        case .shelf: IslandTheme.download
        case .stats: IslandTheme.statCPU
        case .camera: Color.white
        case .calendar: IslandTheme.danger
        case .tasks: IslandTheme.tasks
        case .awake: IslandTheme.keepAwake
        case .base64: IslandTheme.swatch
        case .tools: IslandTheme.tools
        case .github: IslandTheme.github
        case .teams: IslandTheme.teams
        case .browser: IslandTheme.link
        }
    }

    public var symbol: String {
        switch self {
        case .focus: "timer"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.full"
        case .stats: "chart.bar"
        case .camera: "camera"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .awake: "cup.and.saucer.fill"
        case .base64: "textformat.abc"
        case .tools: "wrench.and.screwdriver.fill"
        case .github: "arrow.triangle.pull"
        case .teams: "bubble.left.and.bubble.right.fill"
        case .browser: "globe"
        }
    }
}

public enum LiveActivityKind: Hashable, CaseIterable {
    case pomodoro, keepAwake, focusMode
    /// Music or a video is playing: the app's icon in a ring on the left, an equalizer on the right.
    case media
}

@Observable
@MainActor
public final class IslandModel {
    public var mode: IslandMode = .collapsed
    /// The tab the island shows. Asking for a tab that is switched off in Settings gives the first tab that is on instead, so
    /// the island never shows a tab the user took out (and returns to the asked-for one if it is switched on again).
    public var selectedTab: IslandTab {
        get {
            let tabs = orderedTabs
            return tabs.contains(requestedTab) ? requestedTab : (tabs.first ?? .focus)
        }
        set { requestedTab = newValue }
    }
    private var requestedTab: IslandTab = .focus
    /// While pinned the island stays open. Not remembered between launches, so Island never opens by surprise.
    public var isPinned = false
    /// Max mode: the open island is as big as most of the screen. It closes by itself like any open island (pin it to keep it
    /// open), and opens big again next time until Max is switched off. Not remembered between launches.
    public var isMax = false
    /// The size the open island's content is laid out at: the usual size, or the Max size set by the panel controller.
    public internal(set) var contentSize: CGSize = IslandMetrics.expandedSize
    public private(set) var activities: Set<LiveActivityKind> = []
    /// The event the island is announcing right now, if any.
    public private(set) var alert: EventAlert?
    /// Space the expanded content leaves at the top so it clears the physical notch. Set by the panel controller.
    public var topInset: CGFloat = 0
    public let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Shows an event alert, replacing any that is showing.
    public func showAlert(_ alert: EventAlert) {
        self.alert = alert
    }

    public func dismissAlert() {
        alert = nil
    }

    public func setActivity(_ kind: LiveActivityKind, active: Bool) {
        if active {
            activities.insert(kind)
        } else {
            activities.remove(kind)
        }
    }

    /// Every tab in the order the user chose (see `TabOrder`), switched off or not: Settings lists these.
    public var allTabsInOrder: [IslandTab] {
        TabOrder.normalized(saved: settings.settings.tabOrder, all: IslandTab.allCases.map(\.rawValue))
            .compactMap(IslandTab.init(rawValue:))
    }

    /// The tabs the island shows: the user's order without the tabs switched off in Settings (never empty). The tab bar and
    /// the swipe both follow it.
    public var orderedTabs: [IslandTab] {
        TabOrder.shown(allTabsInOrder.map(\.rawValue), hidden: settings.settings.hiddenTabs)
            .compactMap(IslandTab.init(rawValue:))
    }

    /// Whether the island shows this tab (it is not switched off in Settings).
    public func isShown(_ tab: IslandTab) -> Bool { orderedTabs.contains(tab) }

    /// Files dropped on the island go to the Shelf, so with the Shelf tab switched off the island does not open for them.
    public var acceptsFileDrops: Bool { isShown(.shelf) }

    /// Files are being dragged toward the island: it shows the Shelf, whatever tab was open (even when it is already
    /// open or pinned), so they can be dropped straight onto it.
    public func fileDragEntered() {
        if acceptsFileDrops { selectedTab = .shelf }
    }

    /// Moves `offset` tabs along the user's order, stopping at the first and last tab.
    public func selectAdjacentTab(_ offset: Int) {
        let tabs = orderedTabs
        guard let index = tabs.firstIndex(of: selectedTab) else {
            selectedTab = tabs.first ?? .focus
            return
        }
        selectedTab = tabs[min(max(index + offset, 0), tabs.count - 1)]
    }
}
