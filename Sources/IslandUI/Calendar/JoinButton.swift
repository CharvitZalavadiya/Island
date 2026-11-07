import SwiftUI
import IslandCore

/// "Join": opens an event's meeting (Google Meet, Zoom, Teams …) in the app or browser that handles it.
struct JoinButton: View {
    let link: MeetingLink
    let action: (MeetingLink) -> Void

    var body: some View {
        Button { action(link) } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill").font(.system(size: 10, weight: .bold))
                Text("Join").font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(IslandTheme.tasks, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Join \(link.provider)")
    }

    /// The normal thing Join does: open the link.
    static func open(_ link: MeetingLink) {
        NSWorkspace.shared.open(link.url)
    }
}
