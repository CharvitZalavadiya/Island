import SwiftUI
import IslandCore

enum IslandMetrics {
    static let expandedSize = CGSize(width: 560, height: 330)
    /// The side of a tool tile on the Tools tab: the same as a mascot tile in the Focus tab.
    static let toolTile: CGFloat = 42
}

/// The content for a tab.
@MainActor
@ViewBuilder
func tabView(for tab: IslandTab, services: IslandServices) -> some View {
    switch tab {
    case .focus:
        FocusTab(services: services)
    case .clipboard:
        ClipboardTab(controller: services.clipboard)
    case .shelf:
        ShelfTab(controller: services.shelf)
    case .stats:
        StatsTab(sampler: services.stats, mixer: services.mixer)
    case .camera:
        CameraTab(controller: services.camera, preview: services.cameraPreview)
    case .calendar:
        CalendarTab(controller: services.calendar)
    case .tasks:
        TasksTab(controller: services.tasks)
    case .awake:
        AwakeTab(services: services)
    case .base64:
        TextToolsTab(controller: services.textTools)
    case .tools:
        ToolsTab(controller: services.tools, nowPlaying: services.nowPlaying)
    }
}

struct RootView: View {
    @Bindable var model: IslandModel
    let services: IslandServices

    var body: some View {
        let expanded = model.mode == .expanded
        // While an event is announced the closed island is a small banner, shaped like the open one.
        let banner = model.alert
        let radii = (expanded || banner != nil) ? NotchShape.expanded : NotchShape.collapsed
        ZStack(alignment: .top) {
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(Color.black)
                .animation(.easeInOut(duration: 0.2), value: expanded)
            if expanded {
                VStack(spacing: 10) {
                    TabBar(model: model, openSettings: { services.showSettings() })
                    tabView(for: model.selectedTab, services: services)
                }
                .padding(.top, model.topInset + 6)
                .padding(.horizontal, 18 + radii.top)
                .padding(.bottom, 18)
                // Laid out once at the final size, whatever size the window is at this moment, and revealed as the
                // window grows. Letting SwiftUI re-flow a whole tab at every step of the growth is what made opening
                // jerky; closing never had the problem because the small wings are cheap to lay out.
                .frame(width: IslandMetrics.expandedSize.width, height: IslandMetrics.expandedSize.height, alignment: .top)
                .transition(.opacity)
            } else if let banner {
                // Clicks and hovering are handled by the panel (it catches the pointer while the island is closed).
                AlertBanner(alert: banner, onJoin: { join($0) })
                    .padding(.top, model.topInset + 4)
                    .padding(.horizontal, 20 + radii.top)
                    .padding(.bottom, 8)
            } else {
                WingsView(activities: model.activities, services: services)
                    .padding(.horizontal, radii.top)
                    .frame(maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: expanded)
        .overlay(alignment: .top) {
            // An alert that arrives while the island is open sits over the top of it; clicking it dismisses it.
            if expanded, let banner {
                AlertBanner(alert: banner, onJoin: { join($0) })
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(width: 340)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    .padding(.top, model.topInset + 6)
                    .contentShape(Rectangle())
                    .onTapGesture { services.alerts.dismissNow() }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Join was pressed on an event banner: open the meeting, and the banner has done its job.
    private func join(_ link: MeetingLink) {
        JoinButton.open(link)
        services.alerts.dismissNow()
    }
}
