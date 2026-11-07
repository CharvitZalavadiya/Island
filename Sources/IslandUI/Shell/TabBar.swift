import SwiftUI
import AppKit

struct TabBar: View {
    @Bindable var model: IslandModel
    var openSettings: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.orderedTabs, id: \.self) { tab in
                Button {
                    model.selectedTab = tab
                } label: {
                    TabIcon(tab: tab)
                        .foregroundStyle(model.selectedTab == tab ? tab.color : Color.white.opacity(0.75))
                        .frame(width: 34, height: 26)
                        .background(model.selectedTab == tab ? tab.color.opacity(0.2) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer(minLength: 0)
            Button {
                model.isPinned.toggle()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.isPinned ? IslandTheme.pin : Color.white)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPinned ? "Unpin: let the island close again" : "Pin: keep the island open")
            Menu {
                Button("Settings…") { openSettings() }
                Divider()
                Button("Quit Island") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Island")
        }
        .foregroundStyle(.white)
    }
}


/// A tab's icon: its SF Symbol, or for GitHub the GitHub mark (there is no GitHub symbol in SF Symbols).
struct TabIcon: View {
    let tab: IslandTab

    var body: some View {
        if tab == .github {
            GitHubMarkView(size: 15)
        } else {
            Image(systemName: tab.symbol)
        }
    }
}
