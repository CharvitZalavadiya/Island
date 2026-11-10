import Foundation

/// Why a cron expression could not be read.
public struct CronProblem: Error, Equatable, Sendable {
    public var message: String
    /// True while the expression just has too few fields (the person is probably still typing it).
    public var isIncomplete: Bool

    public init(_ message: String, isIncomplete: Bool = false) {
        self.message = message
        self.isIncomplete = isIncomplete
    }
}

/// A cron schedule such as `30 14 * * *`: read, put into words, and worked out for its next run times.
///
/// Understands the usual five fields (minute hour day-of-month month day-of-week), six with seconds in front, seven with
/// a year at the end, `*`, `?`, lists (`1,15`), ranges (`1-5`), steps (`*/10`, `0-30/5`), month and day names
/// (`JAN`, `mon-fri`), and the `@daily`-style shortcuts.
public struct CronExpression: Equatable, Sendable {
    /// One field of the expression, as written and as the numbers it stands for.
    struct Field: Equatable, Sendable {
        enum Part: Equatable, Sendable {
            case value(Int)
            case range(Int, Int)
            /// Every `every`-th number from `from` through `through`. `full` when that is the field's whole range (`*/n`).
            case step(from: Int, through: Int, every: Int, full: Bool)
        }

        var parts: [Part]
        /// `*` or `?`: no restriction.
        var isAny: Bool
        /// Every number the field allows, in order (a day of week 7 counts as 0, Sunday).
        var values: [Int]
    }

    var seconds: Field?
    var minutes: Field
    var hours: Field
    var daysOfMonth: Field
    var months: Field
    var daysOfWeek: Field
    var years: Field?
    var runsAtStartup = false

    // MARK: Reading

    /// Reads an expression. Fewer than five fields is reported as incomplete (the person may still be typing).
    public static func parse(_ text: String) -> Result<CronExpression, CronProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { return parseShortcut(trimmed.lowercased()) }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 5 else {
            return .failure(CronProblem(
                "A cron expression has 5 fields: minute, hour, day of month, month, day of week.", isIncomplete: true))
        }
        guard words.count <= 7 else {
            return .failure(CronProblem("Too many fields: a cron expression has 5 (or 6 with seconds, 7 with a year), not \(words.count)."))
        }
        // Six fields start with seconds, seven also end with a year.
        let hasSeconds = words.count >= 6
        let hasYear = words.count == 7
        let offset = hasSeconds ? 1 : 0

        do {
            let seconds = hasSeconds ? try parseField(words[0], .second) : nil
            let minutes = try parseField(words[offset], .minute)
            let hours = try parseField(words[offset + 1], .hour)
            let daysOfMonth = try parseField(words[offset + 2], .dayOfMonth)
            let months = try parseField(words[offset + 3], .month)
            let daysOfWeek = try parseField(words[offset + 4], .dayOfWeek)
            let years = hasYear ? try parseField(words[6], .year) : nil
            return .success(CronExpression(
                seconds: seconds, minutes: minutes, hours: hours, daysOfMonth: daysOfMonth, months: months,
                daysOfWeek: daysOfWeek, years: years))
        } catch let problem as CronProblem {
            return .failure(problem)
        } catch {
            return .failure(CronProblem("This isn't a cron expression."))
        }
    }

    private static func parseShortcut(_ text: String) -> Result<CronExpression, CronProblem> {
        switch text {
        case "@yearly", "@annually": return parse("0 0 1 1 *")
        case "@monthly": return parse("0 0 1 * *")
        case "@weekly": return parse("0 0 * * 0")
        case "@daily", "@midnight": return parse("0 0 * * *")
        case "@hourly": return parse("0 * * * *")
        case "@reboot":
            guard case .success(var expression) = parse("0 0 * * *") else { return .failure(CronProblem("Unreadable.")) }
            expression.runsAtStartup = true
            return .success(expression)
        default:
            return .failure(CronProblem("Unknown shortcut \(text). Try @hourly, @daily, @weekly, @monthly, @yearly or @reboot."))
        }
    }

    // MARK: Fields

    private enum Kind {
        case second, minute, hour, dayOfMonth, month, dayOfWeek, year

        var title: String {
            switch self {
            case .second: "Second"
            case .minute: "Minute"
            case .hour: "Hour"
            case .dayOfMonth: "Day of month"
            case .month: "Month"
            case .dayOfWeek: "Day of week"
            case .year: "Year"
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .second, .minute: 0...59
            case .hour: 0...23
            case .dayOfMonth: 1...31
            case .month: 1...12
            case .dayOfWeek: 0...7
            case .year: 1970...2199
            }
        }

        var names: [String: Int] {
            switch self {
            case .month:
                return Dictionary(uniqueKeysWithValues: monthAbbreviations.enumerated().map { ($1, $0 + 1) })
            case .dayOfWeek:
                return Dictionary(uniqueKeysWithValues: dayAbbreviations.enumerated().map { ($1, $0) })
            default:
                return [:]
            }
        }
    }

    private static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let dayAbbreviations = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    private static func parseField(_ text: String, _ kind: Kind) throws -> Field {
        let range = kind.range
        if text == "*" || text == "?" {
            return Field(parts: [], isAny: true, values: expand([], kind))
        }
        var parts: [Field.Part] = []
        for token in text.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard !token.isEmpty else { throw CronProblem("\(kind.title): there is an empty entry in the list.") }
            let pieces = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2 else { throw CronProblem("\(kind.title): \"\(token)\" has more than one step.") }
            var every: Int?
            if pieces.count == 2 {
                guard let step = Int(pieces[1]), step > 0 else {
                    throw CronProblem("\(kind.title): the step in \"\(token)\" must be a positive number.")
                }
                every = step
            }
            let base = pieces[0]
            if base == "*" {
                guard let every else { throw CronProblem("\(kind.title): \"*\" can't be part of a list.") }
                parts.append(.step(from: range.lowerBound, through: kind == .dayOfWeek ? 6 : range.upperBound, every: every, full: true))
            } else if base.contains("-") {
                let ends = base.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard ends.count == 2 else { throw CronProblem("\(kind.title): \"\(base)\" isn't a range.") }
                let low = try parseValue(ends[0], kind), high = try parseValue(ends[1], kind)
                guard low <= high else { throw CronProblem("\(kind.title): the range \"\(base)\" ends before it starts.") }
                if let every { parts.append(.step(from: low, through: high, every: every, full: false)) } else { parts.append(.range(low, high)) }
            } else {
                let value = try parseValue(base, kind)
                if let every {
                    parts.append(.step(from: value, through: kind == .dayOfWeek ? 6 : range.upperBound, every: every, full: false))
                } else {
                    parts.append(.value(value))
                }
            }
        }
        return Field(parts: parts, isAny: false, values: expand(parts, kind))
    }

    private static func parseValue(_ text: String, _ kind: Kind) throws -> Int {
        if let number = Int(text) {
            guard kind.range.contains(number) else {
                throw CronProblem("\(kind.title): \(number) is out of range (\(kind.range.lowerBound)–\(kind.range.upperBound)).")
            }
            return number
        }
        if let named = kind.names[text.uppercased()] { return named }
        let quartz = text.contains(where: { "LW#".contains($0) })
        throw CronProblem(
            "\(kind.title): \"\(text)\" isn't a value Island understands"
                + (quartz ? " (the special symbols L, W and # aren't supported)." : "."))
    }

    private static func expand(_ parts: [Field.Part], _ kind: Kind) -> [Int] {
        var all = Set<Int>()
        if parts.isEmpty {
            // "*": everything the field allows (the days of the week are 0 to 6).
            let upper = kind == .dayOfWeek ? 6 : kind.range.upperBound
            all.formUnion(kind.range.lowerBound...upper)
        }
        for part in parts {
            switch part {
            case .value(let value): all.insert(value)
            case .range(let low, let high): all.formUnion(low...high)
            case .step(let from, let through, let every, _): all.formUnion(stride(from: from, through: through, by: every))
            }
        }
        if kind == .dayOfWeek { all = Set(all.map { $0 % 7 }) }   // 7 is Sunday too
        return all.sorted()
    }

    // MARK: In words

    /// The schedule as a sentence: "At 14:30 every day". `use24Hour` chooses between 14:30 and 2:30 PM.
    public func summary(use24Hour: Bool = true) -> String {
        if runsAtStartup { return "Once, each time the system starts up" }
        let words = Words(use24Hour: use24Hour)
        let time = timePhrase(words)

        var text = time.text
        if let seconds, !(seconds.values == [0] && !seconds.isAny) {
            text = secondsPhrase(seconds, rest: time, words: words)
        }

        var clauses: [String] = []
        let day = dayPhrase(words)
        // "Every 5 minutes, every day" says nothing more than "Every 5 minutes".
        if !(day == "every day" && time.recurring) { clauses.append(day) }
        if !months.isAny { clauses.append(monthPhrase(words)) }
        if let years, !years.isAny { clauses.append(yearPhrase(years, words)) }
        guard !clauses.isEmpty else { return text }
        return text + (time.recurring ? ", " : " ") + clauses.joined(separator: ", ")
    }

    private struct Words {
        let use24Hour: Bool

        /// 14:30, or 2:30 PM.
        func clock(_ hour: Int, _ minute: Int) -> String {
            if use24Hour { return String(format: "%02d:%02d", hour, minute) }
            return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM")
        }

        /// "a", "a and b", "a, b and c".
        func list(_ items: [String]) -> String {
            switch items.count {
            case 0: return ""
            case 1: return items[0]
            default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
            }
        }

        static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }

    private enum Shape {
        case any
        case step(from: Int, through: Int, every: Int, full: Bool)
        case explicit([Int])
    }

    private static func shape(_ field: Field) -> Shape {
        if field.isAny { return .any }
        if field.parts.count == 1, case .step(let from, let through, let every, let full) = field.parts[0] {
            return .step(from: from, through: through, every: every, full: full)
        }
        return .explicit(field.values)
    }

    private func timePhrase(_ words: Words) -> (text: String, recurring: Bool) {
        let minute = Self.shape(minutes), hour = Self.shape(hours)

        switch (minute, hour) {
        case (.any, .any):
            return ("Every minute", true)

        case (.step(let from, let through, let every, let full), .any):
            return (everyPhrase(every, "minute", from: from, through: through, full: full), true)

        case (.explicit(let list), .any):
            if list == [0] { return ("Every hour, on the hour", true) }
            return ("At \(minuteList(list)) past every hour", true)

        case (.explicit(let minuteValues), .explicit(let hourValues)) where minuteValues.count * hourValues.count <= 8:
            let times = hourValues.flatMap { hour in minuteValues.map { words.clock(hour, $0) } }
            return ("At " + words.list(times), false)

        case (.explicit(let minuteValues), .explicit(let hourValues)):
            return ("At \(minuteList(minuteValues)) past \(hourSpan(hourValues, words))", true)

        case (.explicit(let list), .step(let from, let through, let every, let full)):
            let hourPart = every == 1 ? "every hour" : "every \(every) hours"
            let window = full ? "" : " from \(words.clock(from, 0)) through \(words.clock(through, 0))"
            if list == [0] { return (hourPart.prefix(1).uppercased() + String(hourPart.dropFirst()) + window, true) }
            return ("At \(minuteList(list)) past \(hourPart)\(window)", true)

        case (.any, _), (.step, _):
            // Every minute, or every few minutes, but only in some hours.
            let minutePart: String
            if case .step(let from, let through, let every, let full) = minute {
                minutePart = everyPhrase(every, "minute", from: from, through: through, full: full)
            } else {
                minutePart = "Every minute"
            }
            return ("\(minutePart), \(hourWindow(hour, words))", true)

        case (.explicit(let list), _):
            return ("At \(minuteList(list)) past \(hourWindow(hour, words))", true)
        }
    }

    /// "Every 5 minutes", "Every minute", "Every 5 minutes from minute 10 through 40".
    private func everyPhrase(_ every: Int, _ unit: String, from: Int, through: Int, full: Bool) -> String {
        var text = every == 1 ? "Every \(unit)" : "Every \(every) \(unit)s"
        if !full { text += " from \(unit) \(from) through \(through)" }
        return text
    }

    /// "minute 30", "minutes 0 and 30", "every minute from 0 through 15".
    private func minuteList(_ values: [Int]) -> String {
        if values.count > 1, let first = values.first, let last = values.last, last - first + 1 == values.count, values.count > 8 {
            return "every minute from \(first) through \(last)"
        }
        let items = values.map(String.init)
        return (values.count == 1 ? "minute " : "minutes ") + Words(use24Hour: true).list(items)
    }

    /// "every hour from 09:00 through 17:00", "hours 9, 12 and 17".
    private func hourSpan(_ values: [Int], _ words: Words) -> String {
        if values.count > 2, let first = values.first, let last = values.last, last - first + 1 == values.count {
            return "every hour from \(words.clock(first, 0)) through \(words.clock(last, 0))"
        }
        return "hour " + words.list(values.map { words.clock($0, 0) })
    }

    /// "between 09:00 and 17:59", "every 2 hours", "during 09:00, 12:00 and 17:00".
    private func hourWindow(_ shape: Shape, _ words: Words) -> String {
        switch shape {
        case .any:
            return "every hour"
        case .step(let from, let through, let every, let full):
            let base = every == 1 ? "every hour" : "every \(every) hours"
            return full ? base : "\(base) between \(words.clock(from, 0)) and \(words.clock(through, 59))"
        case .explicit(let values):
            guard let first = values.first, let last = values.last else { return "" }
            if last - first + 1 == values.count { return "between \(words.clock(first, 0)) and \(words.clock(last, 59))" }
            return "during " + words.list(values.map { words.clock($0, 0) })
        }
    }

    private func secondsPhrase(_ seconds: Field, rest: (text: String, recurring: Bool), words: Words) -> String {
        let lead: String
        switch Self.shape(seconds) {
        case .any: lead = "Every second"
        case .step(let from, let through, let every, let full):
            lead = everyPhrase(every, "second", from: from, through: through, full: full)
        case .explicit(let values):
            lead = "At second " + words.list(values.map(String.init))
        }
        // "Every 10 seconds" already covers "every minute"; anything narrower is added after it.
        if rest.text == "Every minute" { return lead }
        return lead + ", " + rest.text.prefix(1).lowercased() + String(rest.text.dropFirst())
    }

    /// "every day", "on Monday through Friday", "on day 1 and 15 of the month", "on day 13 of the month and on Friday".
    private func dayPhrase(_ words: Words) -> String {
        var clauses: [String] = []
        if !daysOfMonth.isAny { clauses.append(dayOfMonthClause(words)) }
        if !daysOfWeek.isAny { clauses.append(dayOfWeekClause(words)) }
        // When both are given, cron runs on days matching either one.
        return clauses.isEmpty ? "every day" : clauses.joined(separator: " and ")
    }

    private func dayOfMonthClause(_ words: Words) -> String {
        var phrases: [String] = []
        var plainValues = 0
        for part in daysOfMonth.parts {
            switch part {
            case .value(let value):
                phrases.append(String(value))
                plainValues += 1
            case .range(let low, let high):
                phrases.append("\(low) through \(high)")
            case .step(let from, let through, let every, let full):
                phrases.append(full ? "every \(every) days" : "every \(every) days from day \(from) through \(through)")
            }
        }
        let hasStep = daysOfMonth.parts.contains { if case .step = $0 { return true } else { return false } }
        if hasStep { return "on " + words.list(phrases) }
        let single = daysOfMonth.parts.count == 1 && plainValues == 1
        return "on day\(single ? "" : "s") " + words.list(phrases) + " of the month"
    }

    private func dayOfWeekClause(_ words: Words) -> String {
        func name(_ value: Int) -> String { Words.dayNames[value % 7] }
        let phrases = daysOfWeek.parts.map { part -> String in
            switch part {
            case .value(let value): return name(value)
            case .range(let low, let high): return "\(name(low)) through \(name(high))"
            case .step(let from, let through, let every, let full):
                return full ? "every \(every) days of the week" : "every \(every) days of the week from \(name(from)) through \(name(through))"
            }
        }
        return "on " + words.list(phrases)
    }

    /// "in June", "in January and July", "in March through May", "every 3 months".
    private func monthPhrase(_ words: Words) -> String {
        func name(_ value: Int) -> String { Words.monthNames[value - 1] }
        let phrases = months.parts.map { part -> String in
            switch part {
            case .value(let value): return name(value)
            case .range(let low, let high): return "\(name(low)) through \(name(high))"
            case .step(let from, let through, let every, let full):
                return full ? "every \(every) months" : "every \(every) months from \(name(from)) through \(name(through))"
            }
        }
        let hasStep = months.parts.contains { if case .step = $0 { return true } else { return false } }
        return (hasStep ? "" : "in ") + words.list(phrases)
    }

    private func yearPhrase(_ years: Field, _ words: Words) -> String {
        let phrases = years.parts.map { part -> String in
            switch part {
            case .value(let value): return String(value)
            case .range(let low, let high): return "\(low) through \(high)"
            case .step(let from, let through, let every, _): return "every \(every) years from \(from) through \(through)"
            }
        }
        return "in " + words.list(phrases)
    }

    // MARK: Next runs

    /// The next `count` times the schedule fires after `date`, in `calendar`'s time zone. Empty for `@reboot`, and when
    /// nothing matches within eight years (an impossible date such as February 30).
    public func nextRuns(count: Int, after date: Date, calendar: Calendar = .current) -> [Date] {
        guard !runsAtStartup, count > 0 else { return [] }
        let secondValues = seconds?.values ?? [0]
        var found: [Date] = []
        var day = calendar.startOfDay(for: date)

        for _ in 0..<(8 * 366 + 2) {
            if matches(day: day, calendar: calendar) {
                for hour in hours.values {
                    for minute in minutes.values {
                        for second in secondValues {
                            guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day),
                                  candidate > date, found.last.map({ candidate > $0 }) ?? true
                            else { continue }
                            found.append(candidate)
                            if found.count == count { return found }
                        }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return found
    }

    private func matches(day: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        guard let month = parts.month, let dayOfMonth = parts.day, let weekday = parts.weekday, let year = parts.year else { return false }
        if !months.values.contains(month) { return false }
        if let years, !years.isAny, !years.values.contains(year) { return false }
        let monthMatches = daysOfMonth.values.contains(dayOfMonth)
        let weekMatches = daysOfWeek.values.contains(weekday - 1)
        // When both the day of the month and the day of the week are restricted, a day matching either one runs.
        switch (daysOfMonth.isAny, daysOfWeek.isAny) {
        case (true, true): return true
        case (false, true): return monthMatches
        case (true, false): return weekMatches
        case (false, false): return monthMatches || weekMatches
        }
    }
}

/// What the Cron box shows for whatever was typed.
public enum CronResult: Equatable, Sendable {
    /// Nothing typed yet.
    case empty
    /// Too few fields so far: the person is probably still typing.
    case incomplete(String)
    case invalid(String)
    case described(summary: String, nextRuns: [Date])
}

public enum CronTool {
    /// Reads `text` and puts it into words with its next run times, as soon as it is typed.
    public static func evaluate(
        _ text: String, use24Hour: Bool, now: Date = Date(), calendar: Calendar = .current, nextRunCount: Int = 5
    ) -> CronResult {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        switch CronExpression.parse(text) {
        case .failure(let problem):
            return problem.isIncomplete ? .incomplete(problem.message) : .invalid(problem.message)
        case .success(let expression):
            let runs = expression.nextRuns(count: nextRunCount, after: now, calendar: calendar)
            var summary = expression.summary(use24Hour: use24Hour)
            // A valid expression that never fires (February 30th) deserves a warning, not a bare description.
            if runs.isEmpty && !expression.runsAtStartup { summary += ". No date matches, so this never runs" }
            return .described(summary: summary, nextRuns: runs)
        }
    }

    /// Whether the Mac's clock is set to 24 hours (rather than AM and PM).
    public static func uses24HourClock(locale: Locale = .current) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
        return !format.contains("a")
    }
}
