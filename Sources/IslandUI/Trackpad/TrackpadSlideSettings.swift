import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IslandCore

extension TrackpadAction {
    var tint: Color {
        switch self {
        case .off: Color.white.opacity(0.35)
        case .volume: IslandTheme.volume
        case .brightness: IslandTheme.keepAwake
        case .seek: IslandTheme.tools
        }
    }
}

/// What sliding one finger along an edge of the trackpad does: a picture of the pad with its four edges (pick one), what sliding
/// along it does, and how it behaves. Fingers on the pad show up in the picture as they touch it. Shown inside a `ToolPopup`.
struct TrackpadSlideSettings: View {
    let controller: TrackpadController
    let settings: SettingsStore

    var body: some View {
        SlidePage(controller: controller, settings: settings.settings)
            // The fingers are followed (so they can be shown) only while this is open.
            .onAppear { controller.setPreviewing(true) }
            .onDisappear { controller.setPreviewing(false) }
    }
}

private struct SlidePage: View {
    let controller: TrackpadController
    let settings: IslandCore.Settings
    @State private var selected: TrackpadEdge = .right

    private static let diagramWidth: CGFloat = 214

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TrackpadDiagram(controller: controller, settings: settings, selected: $selected, width: Self.diagramWidth)
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.diagramWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                edgeControls
                sliders
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var edgeControls: some View {
        let action = settings.trackpadAction(for: selected)
        let reversed = settings.trackpadIsReversed(selected)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(selected.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if action != .off {
                    Text("Reverse").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    Toggle("Reverse direction", isOn: Binding(get: { reversed }, set: { controller.setReversed($0, for: selected) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(IslandTheme.accent)
                }
            }
            .frame(height: 18)
            HStack(spacing: 5) {
                ForEach(TrackpadAction.allCases, id: \.self) { choice in
                    ChoicePill(title: choice.title, symbol: choice.symbol, tint: choice.tint, isSelected: choice == action) {
                        controller.setAction(choice, for: selected)
                    }
                }
            }
            Text(Self.hint(edge: selected, action: action, reversed: reversed))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .topLeading)
        }
    }

    private var sliders: some View {
        VStack(spacing: 2) {
            sliderRow(
                "Edge width", value: Binding(get: { settings.trackpadEdgeMM }, set: { controller.setEdgeMM($0) }),
                range: TrackpadDefaults.edgeMMRange, text: "\(Int(settings.trackpadEdgeMM.rounded())) mm")
            sliderRow(
                "Speed", value: Binding(get: { settings.trackpadSensitivity }, set: { controller.setSensitivity($0) }),
                range: TrackpadDefaults.sensitivityRange, text: String(format: "%.1f×", settings.trackpadSensitivity))
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5)).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range).tint(IslandTheme.accent)
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private static func hint(edge: TrackpadEdge, action: TrackpadAction, reversed: Bool) -> String {
        guard action != .off else { return "Sliding along this edge does nothing." }
        let (forward, back) = edge.runsUpAndDown ? ("up", "down") : ("right", "left")
        let (a, b) = reversed ? (back, forward) : (forward, back)
        let more = action == .seek ? "skips ahead" : "goes up"
        let less = action == .seek ? "goes back" : "goes down"
        let note = action == .seek ? " Needs a song or video playing that can be skipped through." : ""
        return "Slide \(a) and it \(more); \(b) and it \(less).\(note)"
    }

    private var statusText: String {
        switch controller.status {
        case .unavailable(let message): message
        case .noTrackpad: "No trackpad was found on this Mac."
        case .off: controller.isEnabled ? "Starting…" : "Off."
        case .running:
            if !controller.isEnabled { "Off. Touch the trackpad to see your finger here." }
            else if controller.framesSeen == 0 { "Touch the trackpad once. No dot? macOS may be blocking it." }
            else { "On. The pointer stays still while you slide along an edge." }
        }
    }
}

private struct ChoicePill: View {
    let title: String
    let symbol: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isSelected ? tint : tint.opacity(0.16), in: Capsule())
            .foregroundStyle(isSelected ? Color.black : tint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

/// The trackpad, drawn to the shape of the real one, with a band along each edge showing what it does.
private struct TrackpadDiagram: View {
    let controller: TrackpadController
    let settings: IslandCore.Settings
    @Binding var selected: TrackpadEdge
    let width: CGFloat

    var body: some View {
        let device = controller.device
        let padWidth = device?.widthMM ?? 122, padHeight = device?.heightMM ?? 74
        let height = width * padHeight / padWidth
        let thickness = CGFloat(settings.trackpadEdgeMM)
        let bandX = thickness / padWidth * width       // how thick the bands on the left and right are
        let bandY = thickness / padHeight * height     // and the ones on the top and bottom
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07))
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
            VStack(spacing: 2) {
                Text("Trackpad").font(.system(size: 11, weight: .semibold))
                if let device { Text("\(Int(device.widthMM.rounded())) × \(Int(device.heightMM.rounded())) mm").font(.system(size: 10)) }
            }
            .foregroundStyle(.white.opacity(0.35))

            band(.left, width: bandX, height: height - 2 * bandY).position(x: bandX / 2, y: height / 2)
            band(.right, width: bandX, height: height - 2 * bandY).position(x: width - bandX / 2, y: height / 2)
            band(.top, width: width - 2 * bandX, height: bandY).position(x: width / 2, y: bandY / 2)
            band(.bottom, width: width - 2 * bandX, height: bandY).position(x: width / 2, y: height - bandY / 2)

            ForEach(controller.touches, id: \.id) { touch in
                Circle()
                    .fill(IslandTheme.accent)
                    .frame(width: 14, height: 14)
                    .shadow(color: IslandTheme.accent.opacity(0.8), radius: 6)
                    .position(x: touch.x * width, y: (1 - touch.y) * height)
            }
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
    }

    private func band(_ edge: TrackpadEdge, width: CGFloat, height: CGFloat) -> some View {
        let action = settings.trackpadAction(for: edge)
        let isSelected = selected == edge
        let busy = controller.edgeInUse == edge
        return RoundedRectangle(cornerRadius: 6)
            .fill(action.tint.opacity(busy ? 0.65 : action == .off ? 0.1 : 0.3))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.white : action.tint.opacity(0.55), lineWidth: isSelected ? 2 : 1))
            .overlay(Image(systemName: action.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(action == .off ? Color.white.opacity(0.4) : action.tint))
            .frame(width: max(width, 1), height: max(height, 1))
            .contentShape(Rectangle())
            .onTapGesture { selected = edge }
            .help(edge.title)
    }
}
