import SwiftUI
import IslandCore

/// The Calendar tab: a month on the left (about 36 %), the selected day's events on the right.
struct CalendarTab: View {
    let controller: CalendarController

    var body: some View {
        ZStack {
            switch controller.access {
            case .authorized:
                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: 14) {
                        CalendarMonthView(controller: controller)
                            .frame(width: proxy.size.width * 0.36)
                        CalendarDayPane(controller: controller)
                    }
                }
            case .notDetermined:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your answer…").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            case .denied:
                accessMessage(
                    "Calendar access is off for Island.",
                    detail: "Turn it on in System Settings to see your events here.",
                    systemImage: "calendar.badge.exclamationmark"
                ) {
                    PillButton(title: "Open Privacy Settings", prominent: true) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .restricted:
                accessMessage(
                    "Calendar access is restricted on this Mac.",
                    detail: "A profile or Screen Time setting is blocking it.",
                    systemImage: "lock.fill"
                ) { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        // The calendar is read only while this tab is on screen.
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }

    private func accessMessage<Action: View>(
        _ title: String, detail: String, systemImage: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(.white.opacity(0.5))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6))
            action()
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: Month

/// The month grid, Sunday to Saturday (or whatever the Mac's first weekday is), like the macOS Calendar widget.
struct CalendarMonthView: View {
    let controller: CalendarController

    var body: some View {
        let calendar = controller.calendar
        let rows = paddedWeeks(MonthGrid.weeks(containing: controller.visibleMonth, calendar: calendar))
        let weekendColumns = MonthGrid.weekendColumns(calendar: calendar)
        let letters = MonthGrid.weekdayLetters(calendar: calendar)
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                arrow("chevron.left", help: "Previous month") { controller.showMonth(byAdding: -1) }
                Spacer(minLength: 0)
                Text(MonthGrid.title(for: controller.visibleMonth, calendar: calendar))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                arrow("chevron.right", help: "Next month") { controller.showMonth(byAdding: 1) }
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    Text(letters[column])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(weekendColumns[column] ? IslandTheme.weekend.opacity(0.85) : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = rows[row][column] {
                            DayCell(
                                day: day, calendar: calendar,
                                isToday: day == controller.today,
                                isSelected: day == controller.selectedDay,
                                hasEvents: controller.daysWithEvents.contains(day),
                                isWeekend: weekendColumns[column]
                            ) { controller.selectDay(day) }
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 24)
                        }
                    }
                }
            }
        }
    }

    /// Always six rows, so the tab keeps its height from month to month.
    private func paddedWeeks(_ weeks: [[Date?]]) -> [[Date?]] {
        weeks + Array(repeating: Array(repeating: nil, count: 7), count: max(6 - weeks.count, 0))
    }

    private func arrow(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// One day of the grid: today is a filled circle, the selected day a ring, Saturday and Sunday are red, and a small
/// dot sits under days that have events.
struct DayCell: View {
    let day: Date
    let calendar: Calendar
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let isWeekend: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isToday {
                    Circle().fill(IslandTheme.calendarToday)
                } else if isSelected {
                    Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? Color.black : (isWeekend ? IslandTheme.weekend : .white))
            }
            .frame(width: 22, height: 22)
            .overlay(alignment: .bottom) {
                if hasEvents {
                    Circle()
                        .fill(isToday ? Color.black.opacity(0.7) : IslandTheme.calendarToday)
                        .frame(width: 3, height: 3)
                        .offset(y: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Day

/// The selected day's title and its events.
struct CalendarDayPane: View {
    let controller: CalendarController

    var body: some View {
        let isToday = controller.selectedDay == controller.today
        let isCurrentMonth = controller.visibleMonth == MonthGrid.month(byAdding: 0, to: controller.today, calendar: controller.calendar)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(isToday: isToday)).font(.system(size: 14, weight: .semibold))
                Spacer()
                if !isToday || !isCurrentMonth {
                    PillButton(title: "Today") { controller.goToToday() }
                }
            }
            if controller.eventsForSelectedDay.isEmpty {
                Spacer()
                Text("No events")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(controller.eventsForSelectedDay) { EventRow(event: $0) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(isToday: Bool) -> String {
        if isToday { return "Today" }
        let formatter = DateFormatter()
        formatter.calendar = controller.calendar
        formatter.locale = controller.calendar.locale ?? .current
        formatter.timeZone = controller.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: controller.selectedDay)
    }
}

/// One event: a bar in its calendar's colour, the time, the title.
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.colorHex.map { Color(hex: $0) } ?? Color.white.opacity(0.4))
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(timeText).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            // Only while the meeting can still be joined.
            if let meeting = event.meeting, event.end > Date() {
                JoinButton(link: meeting, action: JoinButton.open)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return event.end > event.start ? "\(start) – \(end)" : start
    }
}
