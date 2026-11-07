import SwiftUI
import IslandCore

/// Every mascot as a tile in a grid you scroll up and down. The first tile is Shuffle (a different mascot each
/// session); the rest pick one mascot. Each tile has its own soft background, and the chosen one is ringed in its own
/// colour.
struct MascotGrid: View {
    let controller: PomodoroController

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 6) {
                    shuffleTile
                    ForEach(MascotRegistry.all) { mascot in tile(for: mascot) }
                }
                .padding(2)
            }
            .onAppear { proxy.scrollTo(controller.mascotID, anchor: .center) }
        }
    }

    private var shuffleTile: some View {
        let on = controller.shuffleOn
        return Button {
            controller.setShuffle(!on)
        } label: {
            // The tile is a flexible square (the grid decides its width); what is drawn in it is laid over it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? Color.black : IslandTheme.focus)
                }
                .background(on ? IslandTheme.focus : IslandTheme.focus.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(on ? "Shuffle is on: a different mascot every session" : "Shuffle: a different mascot every session")
    }

    private func tile(for mascot: MascotDefinition) -> some View {
        let selected = controller.mascotID == mascot.id
        return Button {
            controller.selectMascot(mascot.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { BlobMascotView(mascot, mood: .focus, size: 28, animated: false) }
                .background(mascot.bodyColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(mascot.bodyColor, lineWidth: selected ? 2 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(mascot.name)
        .id(mascot.id)
    }
}
