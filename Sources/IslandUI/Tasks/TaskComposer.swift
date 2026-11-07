import SwiftUI
import IslandCore

/// The row for adding a task: a field, a button for a time (30 minutes, an hour, this evening, tomorrow morning, or a
/// date and time you pick), and Add. Used for Island's own list and for Todoist.
///
/// `onAdd` says whether the task was added. The text stays in the field until it was, so a task that could not be added
/// (no internet, say) is not lost.
struct TaskComposer: View {
    let placeholder: String
    let onAdd: (String, Date?) async -> Bool

    @State private var title = ""
    @State private var due: Date?
    @State private var showsPicker = false
    @State private var isAdding = false
    @State private var selection = DueTimeSelection(rounding: Date().addingTimeInterval(3600))
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            row
            if showsPicker {
                TaskTimePicker(
                    selection: $selection, now: Date(),
                    onSet: {
                        due = selection.date()
                        showsPicker = false
                    },
                    onCancel: { showsPicker = false })
            }
        }
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: titleFocused) { _, focused in
            if focused { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus").foregroundStyle(IslandTheme.tasks)
                TextField(placeholder, text: $title)
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
                    .background(IslandTheme.tasks.opacity(trimmedTitle.isEmpty || isAdding ? 0.35 : 1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty || isAdding)
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

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmedTitle.isEmpty, !isAdding else { return }
        let text = trimmedTitle, when = due
        isAdding = true
        Task {
            let added = await onAdd(text, when)
            isAdding = false
            if added {
                title = ""
                due = nil
            }
        }
    }
}
