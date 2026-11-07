import SwiftUI
import IslandCore

/// Picks a day and a time for a task: chips for the next few days, then hour and minute wheels (and AM/PM on a 12-hour
/// clock).
struct TaskTimePicker: View {
    @Binding var selection: DueTimeSelection
    let now: Date
    let onSet: () -> Void
    let onCancel: () -> Void

    private let tint = IslandTheme.tasks
    private let twentyFourHour = TaskDue.usesTwentyFourHourClock()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(TaskDue.dayOptions(now: now), id: \.day) { option in
                    let selected = Calendar.current.isDate(option.day, inSameDayAs: selection.day)
                    Button { selection.day = option.day } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(selected ? tint : Color.white.opacity(0.1), in: Capsule())
                            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 0) {
                    NumberWheel(
                        value: hourBinding, values: twentyFourHour ? Array(0...23) : Array(1...12),
                        format: { twentyFourHour ? String(format: "%02d", $0) : "\($0)" }
                    )
                    .frame(width: 50)
                    Text(":").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                    NumberWheel(
                        value: Binding(get: { selection.minute }, set: { selection.minute = $0 }),
                        values: Array(stride(from: 0, through: 55, by: 5)), format: { String(format: "%02d", $0) }
                    )
                    .frame(width: 50)
                    if !twentyFourHour {
                        VStack(spacing: 4) {
                            meridiem("AM", isPM: false)
                            meridiem("PM", isPM: true)
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 12)
                .background {
                    // The row in the middle of the wheels is the one that counts.
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)).frame(height: 24).padding(.horizontal, 6)
                }
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text(preview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPast ? IslandTheme.danger : .white.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        PillButton(title: "Set time", prominent: true, tint: tint, action: onSet)
                        PillButton(title: "Cancel", action: onCancel)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var isPast: Bool { selection.date() < now }

    private var preview: String {
        let label = TaskDue.label(for: selection.date(), now: now)
        return isPast ? "\(label.text)\nThat time has passed." : label.text
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { twentyFourHour ? selection.hour24 : selection.hour12 },
            set: { hour in
                if twentyFourHour { selection.hour24 = hour } else { selection.setHour12(hour, isPM: selection.isPM) }
            })
    }

    private func meridiem(_ title: String, isPM: Bool) -> some View {
        let selected = selection.isPM == isPM
        return Button { selection.setHour12(selection.hour12, isPM: isPM) } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 34, height: 22)
                .background(selected ? tint : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A vertical wheel of numbers: scroll to turn it, and the one in the middle is chosen.
struct NumberWheel: View {
    @Binding var value: Int
    let values: [Int]
    var format: (Int) -> String = { "\($0)" }
    private let rowHeight: CGFloat = 24
    @State private var position: Int?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { number in
                    Text(format(number))
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .id(number)
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.3)
                                .scaleEffect(phase.isIdentity ? 1 : 0.8)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, rowHeight, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .frame(height: rowHeight * 3)
        .onAppear { position = value }
        .onChange(of: position) { _, new in
            if let new, new != value { value = new }
        }
        .onChange(of: value) { _, new in
            if position != new { position = new }
        }
    }
}
