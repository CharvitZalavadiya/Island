import SwiftUI
import QuickLookThumbnailing
import IslandCore

struct ShelfTab: View {
    let controller: ShelfController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drop files on the island to keep them here. Click to select, drag out to copy.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            if controller.items.isEmpty {
                Spacer()
                Image(systemName: "tray.and.arrow.down")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                        ForEach(controller.items) { item in
                            ShelfTile(item: item, controller: controller)
                        }
                    }
                    // Room above and beside the tiles: the check mark sits half outside a tile's corner, and the
                    // scrolling area would cut it off at the top of the first row.
                    .padding(.top, 10)
                    .padding(.horizontal, 6)
                }
            }

            if !controller.selectedIDs.isEmpty {
                ShelfActionBar(controller: controller)
            }

            if let message = controller.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let controller: ShelfController

    var body: some View {
        let url = controller.url(for: item)
        ShelfTileFace(item: item, url: url, selected: controller.selectedIDs.contains(item.id))
            // The whole tile is one drag source: a click selects it, a drag copies the file out (see FileDragSource).
            // A file that has vanished has no URL, so it can be selected (and removed) but not dragged.
            .overlay { FileDragSource(url: url, onClick: { controller.toggleSelection(item) }) }
            .help(url == nil ? "\(item.displayName) is no longer there. Select it and choose Remove." : item.displayName)
    }
}

/// How a tile looks: thumbnail, name, and a cyan ring with a check when selected.
struct ShelfTileFace: View {
    let item: ShelfItem
    /// Nil when the file has vanished; the tile is then dimmed.
    let url: URL?
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // The preview itself is the tile: a rectangle with a slightly rounded corner, filled with the file's picture.
                FileThumbnail(url: url)
                    .frame(width: 76, height: 60)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(IslandTheme.accent, lineWidth: selected ? 2 : 0)
                    }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.black, IslandTheme.accent)
                        .offset(x: 5, y: -5)
                } else if item.isScreenshot {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 10))
                        .padding(3)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .offset(x: -2, y: 2)
                }
            }
            Text(item.displayName)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84)
        }
        .frame(width: 88)
        .padding(.vertical, 3)
        .background(selected ? IslandTheme.accentSoft.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .opacity(url == nil ? 0.4 : 1)
    }
}

/// Pinned under the grid while something is selected: only the actions that make sense for the selection.
struct ShelfActionBar: View {
    let controller: ShelfController

    var body: some View {
        let actions = controller.actions
        HStack(spacing: 6) {
            Text("\(controller.selectedIDs.count) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandTheme.accent)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            // Convert (only when every selected file is an image) sits furthest left, then Zip and AirDrop.
            if !actions.convertFormats.isEmpty {
                Menu {
                    ForEach(actions.convertFormats, id: \.self) { format in
                        Button(format.label) { Task { await controller.convertSelected(to: format) } }
                    }
                } label: {
                    BarLabel(title: "Convert to", symbol: "arrow.triangle.2.circlepath", trailing: "chevron.down")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if actions.canZip {
                BarButton(title: "Zip", symbol: "doc.zipper") { Task { await controller.zipSelected() } }
            }
            if actions.canUnzip {
                BarButton(title: "Unzip", symbol: "arrow.up.bin") { Task { await controller.unzipSelected() } }
            }
            if actions.canAirDrop {
                BarButton(title: "AirDrop", symbol: "airplayaudio") { controller.airDropSelected() }
            }
            if actions.canShowInFinder {
                BarButton(title: "Show in Finder", symbol: "folder") { controller.showSelectedInFinder() }
            }
            if actions.canRemove {
                BarButton(title: "Remove", symbol: "xmark.circle") { controller.removeSelected() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { BarLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
    }
}

private struct BarLabel: View {
    let title: String
    let symbol: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
            if let trailing { Image(systemName: trailing).font(.system(size: 8, weight: .bold)) }
        }
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(IslandTheme.accentSoft, in: Capsule())
        .foregroundStyle(IslandTheme.accent)
        .contentShape(Capsule())
    }
}

extension ImageFormat {
    var label: String {
        switch self {
        case .heic: "HEIC"
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .tiff: "TIFF"
        case .pdf: "PDF"
        }
    }
}

/// A Quick Look preview of a file, or a plain document icon until it loads (or if there is no file). A real preview fills
/// the whole rectangle (cropped to it); a generic file icon is shown whole.
struct FileThumbnail: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var isGenericIcon = false

    var body: some View {
        Group {
            if let image {
                if isGenericIcon {
                    Image(nsImage: image).resizable().scaledToFit().padding(8)
                } else {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                Image(systemName: "doc").font(.title2).foregroundStyle(.white.opacity(0.5))
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 152, height: 120), scale: 2, representationTypes: .all)
            let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            isGenericIcon = representation?.type == .icon
            image = representation?.nsImage
        }
    }
}
