import SwiftUI
import IslandCore

/// The Tasks tab: add a task (with an optional time), tick it off, and look back at what is done. A switch at the top,
/// like the Pomodoro's, changes between the Active and the Completed list.
struct TasksTab: View {
    @Bindable var controller: TasksController

    @State private var title = ""
    @State private var due: Date?
    @State private var showsPicker = false
    @State private var selection = DueTimeSelection(rounding: Date().addingTimeInterval(3600))
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TaskModeSwitch(
                    mode: $controller.mode, activeCount: controller.activeCount, completedCount: controller.completedCount)
                Spacer(minLength: 4)
                if controller.mode == .completed, controller.completedCount > 0 {
                    PillButton(title: "Clear completed", prominent: false, tint: IslandTheme.danger) {
                        controller.clearCompleted()
                    }
                }
            }

            if controller.mode == .active {
                addRow
                if showsPicker { pickerRow }
            }

            let tasks = controller.visible
            if tasks.isEmpty {
                Spacer()
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { task in
                            TaskRow(task: task, onToggle: { controller.toggle(task) }, onDelete: { controller.remove(task) })
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(.white)
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: titleFocused) { _, focused in
            if focused { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var emptyText: String {
        controller.mode == .active ? "Nothing to do. Add a task above." : "Nothing completed yet."
    }

    // MARK: Adding

    private var addRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus").foregroundStyle(IslandTheme.tasks)
                TextField("Add a task", text: $title)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit(add)
                if let due {
                    let label = TaskDue.label(for: due, now: Date())
                    Button { self.due = nil } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(label.text)
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(IslandTheme.tasks.opacity(0.2), in: Capsule())
                        .foregroundStyle(IslandTheme.tasks)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the time")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.1), in: Capsule())

            timeMenu
            Button(action: add) {
                Text("Add")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(IslandTheme.tasks.opacity(trimmedTitle.isEmpty ? 0.35 : 1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty)
        }
    }

    private var timeMenu: some View {
        Menu {
            ForEach(TaskDue.presets(now: Date()), id: \.title) { preset in
                Button(preset.title) { due = preset.date }
            }
            Divider()
            Button("Pick date and time…") {
                selection = DueTimeSelection(rounding: due ?? Date().addingTimeInterval(3600))
                showsPicker = true
            }
            if due != nil { Button("No time") { due = nil } }
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IslandTheme.tasks)
                .frame(width: 30, height: 30)
                .background(IslandTheme.tasks.opacity(0.18), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set a time for this task")
    }

    private var pickerRow: some View {
        TaskTimePicker(
            selection: $selection, now: Date(),
            onSet: {
                due = selection.date()
                showsPicker = false
            },
            onCancel: { showsPicker = false })
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmedTitle.isEmpty else { return }
        controller.add(title: title, due: due)
        title = ""
        due = nil
    }
}

/// The "Active | Completed" switch at the top of the tab, in the style of the Pomodoro | Stopwatch one.
struct TaskModeSwitch: View {
    @Binding var mode: TasksController.Mode
    let activeCount: Int
    let completedCount: Int

    var body: some View {
        HStack(spacing: 2) {
            segment("Active", count: activeCount, selected: mode == .active) { mode = .active }
            segment("Completed", count: completedCount, selected: mode == .completed) { mode = .completed }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: Capsule())
    }

    private func segment(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(count > 0 ? "\(title) \(count)" : title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selected ? IslandTheme.tasks : Color.clear, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One task: the checkbox on the left, the title (struck through once done) and the time on the right.
struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isCompleted ? IslandTheme.tasks : Color.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Mark as not done" : "Mark as done")

            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .strikethrough(task.isCompleted, color: .white.opacity(0.5))
                .foregroundStyle(task.isCompleted ? Color.white.opacity(0.4) : Color.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let due = task.due {
                let label = TaskDue.label(for: due, now: Date())
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(label.text)
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(
                    task.isCompleted ? Color.white.opacity(0.3) : (label.isOverdue ? IslandTheme.danger : Color.white.opacity(0.6)))
            }
            // The delete button appears only while the pointer is on the row, so the row keeps its shape.
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandTheme.danger)
                    .frame(width: 24, height: 24)
                    .background(IslandTheme.danger.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help("Delete this task")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
    }
}
