import SwiftUI
import IslandCore

/// Which tasks the Tasks tab shows: Island's own list, or the person's Todoist.
enum TasksSource: String, Hashable {
    case local
    case todoist
}

/// The Tasks tab. A switch at the top changes between the Active and the Completed list, like the Pomodoro's; a second one
/// at the right changes between Island's own tasks (Local) and the person's Todoist. The choice is remembered.
struct TasksTab: View {
    @Bindable var controller: TasksController
    @Bindable var todoist: TodoistController
    let settings: SettingsStore

    private var source: TasksSource { TasksSource(rawValue: settings.settings.tasksSource) ?? .local }

    private var sourceBinding: Binding<TasksSource> {
        Binding(get: { source }, set: { chosen in settings.update { $0.tasksSource = chosen.rawValue } })
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            switch source {
            case .local: LocalTasksContent(controller: controller)
            case .todoist: TodoistPane(todoist: todoist)
            }
        }
        .foregroundStyle(.white)
        // Todoist is only asked about while its view is on screen: opening the tab on Todoist loads it, leaving stops it.
        .task(id: source) {
            if source == .todoist { await todoist.start() } else { todoist.stop() }
        }
        .onDisappear { todoist.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch source {
            case .local:
                TaskModeSwitch(
                    mode: $controller.mode, activeCount: controller.activeCount, completedCount: controller.completedCount)
            case .todoist:
                if todoist.connection == .connected {
                    TaskModeSwitch(
                        mode: $todoist.mode, activeCount: todoist.activeCount, completedCount: todoist.completedCount)
                }
            }
            Spacer(minLength: 4)
            if source == .local, controller.mode == .completed, controller.completedCount > 0 {
                PillButton(title: "Clear completed", prominent: false, tint: IslandTheme.danger) {
                    controller.clearCompleted()
                }
            }
            if source == .todoist, todoist.connection == .connected { TodoistMenu(todoist: todoist) }
            PillSwitch(selection: sourceBinding, options: [(.local, "Local"), (.todoist, "Todoist")], tint: IslandTheme.tasks)
        }
    }
}

/// Island's own list: add a task (with an optional time), tick it off, and look back at what is done.
struct LocalTasksContent: View {
    @Bindable var controller: TasksController

    var body: some View {
        VStack(spacing: 10) {
            if controller.mode == .active {
                TaskComposer(placeholder: "Add a task") { title, due in
                    controller.add(title: title, due: due)
                    return true
                }
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
    }

    private var emptyText: String {
        controller.mode == .active ? "Nothing to do. Add a task above." : "Nothing completed yet."
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
