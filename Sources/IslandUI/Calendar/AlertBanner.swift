import SwiftUI
import IslandCore

/// "Design review, starts in 10 min": what the island shows shortly before an event. An online meeting also has a Join
/// button.
struct AlertBanner: View {
    let alert: EventAlert
    /// Called when Join is pressed (opens the meeting and puts the banner away).
    var onJoin: (MeetingLink) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(alert.colorHex.map { Color(hex: $0) } ?? IslandTheme.accent)
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                // The countdown is only redrawn every 15 seconds: the banner is up for ten seconds, a little longer
                // when the pointer is held over it.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("\(Self.countdown(start: alert.start, now: context.date)) · \(alert.start.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(alert.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if let meeting = alert.meeting {
                JoinButton(link: meeting, action: onJoin)
            }
        }
    }

    /// "Starts in 10 min", counted to the nearest minute (so an alert that fires exactly ten minutes ahead still says
    /// 10 when it is drawn a moment later).
    static func countdown(start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "Starting now" }
        if seconds < 60 { return "Starts in under a minute" }
        return "Starts in \(Int((seconds / 60).rounded())) min"
    }
}
