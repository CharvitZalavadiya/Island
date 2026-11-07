import SwiftUI
import IslandCore

/// The Awake tab: the tools for a stuck Mac. On the left, stop a program or free a port; on the right, keep the Mac
/// awake (the same panel as before).
struct AwakeTab: View {
    let services: IslandServices

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                ProcessToolsPanel(controller: services.processTools)
                    .frame(width: proxy.size.width * 0.62, alignment: .topLeading)
                Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 10)
                KeepAwakeCard(viewModel: services.keepAwake)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Search for a program (or a port) and stop it.
struct ProcessToolsPanel: View {
    @Bindable var controller: ProcessToolsController
    @FocusState private var searchFocused: Bool

    private let tint = IslandTheme.danger

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PillSwitch(
                    selection: Binding(get: { controller.mode }, set: { mode in Task { await controller.setMode(mode) } }),
                    options: [(.processes, "Processes"), (.ports, "Ports")], tint: tint)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField(controller.mode == .processes ? "Search a program" : "Search a port, like 3000", text: $controller.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(0.1), in: Capsule())

            // One fixed line for what just happened, so the list does not jump.
            Text(controller.message?.text ?? " ")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color(for: controller.message?.tone))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)

            list
        }
        .foregroundStyle(.white)
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: searchFocused) { _, focused in
            if focused { NSApp.activate(ignoringOtherApps: true) }
        }
        // Read the list when the tab appears, and again every few seconds while it stays on screen.
        .task(id: controller.mode) {
            while !Task.isCancelled {
                await controller.refresh()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if controller.mode == .processes {
            let matches = controller.processMatches
            if matches.isEmpty {
                placeholder("No program matches.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(matches) { match in
                            KillRow(
                                title: match.name,
                                subtitle: [match.app.map { "in \($0)" }, "pid \(match.pid)", StatsFormat.appMemory(match.residentBytes)]
                                    .compactMap { $0 }.joined(separator: " · "),
                                state: state(for: match.pid)
                            ) { Task { await controller.tapKill(pid: match.pid, name: match.name) } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        } else {
            let matches = controller.portMatches
            if let free = controller.freePort {
                FreePortRow(port: free)
            } else if matches.isEmpty {
                placeholder("Nothing is listening.")
            }
            if !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(matches) { listener in
                            KillRow(
                                title: "Port \(listener.port)",
                                subtitle: "\(listener.command) · pid \(listener.pid) · \(listener.address)",
                                state: state(for: listener.pid)
                            ) { Task { await controller.tapKill(pid: listener.pid, name: listener.command, port: listener.port) } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func state(for pid: Int) -> KillRow.State {
        if controller.armedPID == pid { return .armed(force: controller.stubborn.contains(pid)) }
        return controller.stubborn.contains(pid) ? .stubborn : .normal
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for tone: ProcessToolsController.Message.Tone?) -> Color {
        switch tone {
        case .good: IslandTheme.tasks
        case .bad: IslandTheme.danger
        default: .white.opacity(0.65)
        }
    }
}

/// One program or port. Its Kill button only appears while the pointer is over the row, so it can't be hit by accident
/// while scrolling or aiming for something else. It stays once it has been tapped, and changes with what has happened:
/// Kill, then Sure?, and Force if the program ignored a polite quit.
struct KillRow: View {
    enum State: Equatable {
        case normal
        case armed(force: Bool)
        case stubborn
    }

    let title: String
    let subtitle: String
    let state: State
    let action: () -> Void
    @SwiftUI.State private var hovering = false

    var body: some View {
        // Armed ("Sure?") and stubborn ("Force") rows keep their button, so a half-finished kill is never hidden.
        let showsButton = hovering || state != .normal
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(solid ? Color.black : IslandTheme.danger)
                    .frame(width: 58, height: 24)
                    .background(solid ? IslandTheme.danger : IslandTheme.danger.opacity(0.18), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showsButton ? 1 : 0)
            .allowsHitTesting(showsButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(hovering ? 0.10 : 0.07), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: showsButton)
    }

    private var solid: Bool {
        if case .armed = state { return true }
        return false
    }

    private var label: String {
        switch state {
        case .normal: "Kill"
        case .armed: "Sure?"
        case .stubborn: "Force"
        }
    }
}

/// Shown when a port number was typed and nothing is using it.
struct FreePortRow: View {
    let port: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandTheme.tasks)
            Text("Port \(port) is free.").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(IslandTheme.tasks.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A row of two or more choices in a pill, like the Pomodoro | Stopwatch switch.
struct PillSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(selection == option.0 ? tint : Color.clear, in: Capsule())
                        .foregroundStyle(selection == option.0 ? Color.black : Color.white.opacity(0.75))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
}
