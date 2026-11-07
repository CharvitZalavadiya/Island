import Foundation

/// The arithmetic behind the month view.
public enum MonthGrid {
    /// The month containing `month` as rows of seven cells, honouring `calendar.firstWeekday`. Cells are start-of-day
    /// dates; `nil` pads the days before the 1st and after the last. A month takes four to six rows.
    public static func weeks(containing month: Date, calendar: Calendar) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
            let dayCount = calendar.range(of: .day, in: .month, for: interval.start)?.count
        else { return [] }
        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first).map(calendar.startOfDay(for:)))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// "S M T W T F S", starting from the calendar's first weekday.
    public static func weekdayLetters(calendar: Calendar) -> [String] {
        let letters = calendar.veryShortStandaloneWeekdaySymbols   // Sunday first
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { letters[($0 + shift) % 7] }
    }

    /// "October 2026" (in the calendar's language).
    public static func title(for month: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: month)
    }

    /// The first day of the month `count` months from the one containing `date`. Starting from the 1st means adding
    /// a month to the 31st cannot skip a short month.
    public static func month(byAdding count: Int, to date: Date, calendar: Calendar) -> Date {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        return calendar.date(byAdding: .month, value: count, to: first) ?? first
    }

    /// Saturday and Sunday, whatever the calendar's first weekday: they are shown in red.
    public static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)   // 1 is Sunday, 7 is Saturday
        return weekday == 1 || weekday == 7
    }

    /// For each of the seven columns, whether it is a weekend day.
    public static func weekendColumns(calendar: Calendar) -> [Bool] {
        (0..<7).map { column in
            let weekday = (calendar.firstWeekday - 1 + column) % 7 + 1
            return weekday == 1 || weekday == 7
        }
    }
}
