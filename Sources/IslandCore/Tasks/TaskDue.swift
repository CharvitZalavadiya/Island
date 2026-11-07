import Foundation

/// How a task's due time is worded and which quick choices are offered for it.
public enum TaskDue {
    public struct Label: Equatable {
        public var text: String
        public var isOverdue: Bool
    }

    /// "Today 5:30 PM", "Tomorrow 9:00 AM", "Fri 6 Nov 9:00 AM"; overdue once the time has passed.
    public static func label(for due: Date, now: Date, calendar: Calendar = .current) -> Label {
        let day: String
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: due)
        let difference = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0
        switch difference {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale ?? .current
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
            day = formatter.string(from: due)
        }
        let time = DateFormatter()
        time.calendar = calendar
        time.locale = calendar.locale ?? .current
        time.timeZone = calendar.timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        return Label(text: "\(day) \(time.string(from: due))", isOverdue: due < now)
    }

    public struct Preset: Equatable {
        public var title: String
        public var date: Date
    }

    /// Quick choices for a due time: in half an hour, in an hour, this evening (only while it is still ahead) and
    /// tomorrow morning.
    public static func presets(now: Date, calendar: Calendar = .current) -> [Preset] {
        var result = [
            Preset(title: "In 30 minutes", date: now.addingTimeInterval(30 * 60)),
            Preset(title: "In 1 hour", date: now.addingTimeInterval(60 * 60)),
        ]
        if let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now), evening > now.addingTimeInterval(60 * 60) {
            result.append(Preset(title: "This evening, 6 PM", date: evening))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
            let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        {
            result.append(Preset(title: "Tomorrow morning, 9 AM", date: morning))
        }
        return result
    }
}
