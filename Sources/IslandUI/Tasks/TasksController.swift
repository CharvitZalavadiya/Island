import Foundation
import Observation
import IslandCore

/// The Tasks tab's state: the list, and which half of it is showing.
@Observable
@MainActor
final class TasksController {
    enum Mode { case active, completed }

    var mode: Mode = .active
    private(set) var items: [TaskItem]
    /// Tasks that were just ticked off: they stay in the Active list, struck through, for a moment before moving to
    /// Completed, so the tick visibly does something.
    private(set) var lingering: Set<UUID> = []

    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let lingerSeconds: TimeInterval
    @ObservationIgnored private var lingerTimers: [UUID: Timer] = [:]

    init(store: TaskStore, lingerSeconds: TimeInterval = 0.8) {
        self.store = store
        self.lingerSeconds = lingerSeconds
        self.items = store.items
    }

    /// What the list shows right now.
    var visible: [TaskItem] {
        switch mode {
        case .active:
            // A task that was only just ticked off is still shown here (struck through) for a moment.
            return items.filter { !$0.isCompleted || lingering.contains($0.id) }
                .sorted(by: TaskStore.isOrderedBeforeInActiveList)
        case .completed:
            return TaskStore.completed(in: items.filter { !lingering.contains($0.id) })
        }
    }

    var activeCount: Int { items.filter { !$0.isCompleted }.count }
    var completedCount: Int { items.filter { $0.isCompleted && !lingering.contains($0.id) }.count }

    func add(title: String, due: Date?) {
        guard store.add(title: title, due: due) != nil else { return }
        refresh()
    }

    /// Ticks a task off (it is struck through, then moves to Completed) or, from the Completed list, puts it back.
    func toggle(_ task: TaskItem) {
        if task.isCompleted && !lingering.contains(task.id) {
            store.setCompleted(task.id, false)
            refresh()
            return
        }
        if lingering.contains(task.id) {
            // Ticked by mistake: un-ticking while it is still lingering brings it straight back.
            endLinger(task.id)
            store.setCompleted(task.id, false)
            refresh()
            return
        }
        let id = task.id
        store.setCompleted(id, true)
        lingering.insert(id)
        refresh()
        lingerTimers[id] = Timer.scheduledTimer(withTimeInterval: lingerSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishLinger(id) }
        }
    }

    func remove(_ task: TaskItem) {
        endLinger(task.id)
        store.remove(task.id)
        refresh()
    }

    func clearCompleted() {
        for id in lingering { endLinger(id) }
        store.clearCompleted()
        refresh()
    }

    // MARK: Internals

    private func finishLinger(_ id: UUID) {
        lingerTimers[id] = nil
        lingering.remove(id)
        refresh()
    }

    private func endLinger(_ id: UUID) {
        lingerTimers[id]?.invalidate()
        lingerTimers[id] = nil
        lingering.remove(id)
    }

    private func refresh() {
        items = store.items
    }
}
