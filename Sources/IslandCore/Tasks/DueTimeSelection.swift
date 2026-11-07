import Foundation

/// What the task time picker has chosen: a day, and a time of day in 5-minute steps. It turns into a date, and a date
/// turns back into it, so the picker can start from a task's existing time.
public struct DueTimeSelection: Equatable {
    /// The start of the chosen day.
    public var day: Date
    /// 0 to 23.
    public var hour24: Int
    /// 0, 5, 10 ... 55.
    public var minute: Int

    public init(day: Date, hour24: Int, minute: Int) {
        self.day = day
        self.hour24 = min(max(hour24, 0), 23)
        self.minute = min(max(minute / 5 * 5, 0), 55)
    }

    /// The selection for `date`, with the time rounded UP to the next 5 minutes (so it is never earlier than asked).
    public init(rounding date: Date, calendar: Calendar = .current) {
        let minutes = calendar.component(.minute, from: date)
        let hasSeconds = calendar.component(.second, from: date) != 0
        let toAdd = minutes % 5 == 0 && !hasSeconds ? 0 : 5 - minutes % 5
        let rounded = calendar.date(byAdding: .minute, value: toAdd, to: date) ?? date
        self.init(
            day: calendar.startOfDay(for: rounded), hour24: calendar.component(.hour, from: rounded),
            minute: calendar.component(.minute, from: rounded))
    }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour24, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: 12-hour clocks

    public var isPM: Bool { hour24 >= 12 }

    /// 1 to 12.
    public var hour12: Int { hour24 % 12 == 0 ? 12 : hour24 % 12 }

    public mutating func setHour12(_ hour: Int, isPM: Bool) {
        hour24 = (hour % 12) + (isPM ? 12 : 0)
    }
}

extension TaskDue {
    public struct DayOption: Equatable {
        public var title: String
        /// The start of that day.
        public var day: Date
    }

    /// The days offered in the picker: today, tomorrow and the four after that ("Wed 4").
    public static func dayOptions(now: Date, calendar: Calendar = .current, count: Int = 6) -> [DayOption] {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let title = offset == 0 ? "Today" : (offset == 1 ? "Tomorrow" : formatter.string(from: day))
            return DayOption(title: title, day: day)
        }
    }

    /// Whether the current locale shows hours on a 24-hour clock.
    public static func usesTwentyFourHourClock(locale: Locale = .current) -> Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
    }
}
