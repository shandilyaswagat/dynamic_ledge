import SwiftUI

/// The user's own tiles on Home (Settings › Home): small buttons that open an app, a website or
/// a folder, or run a Shortcut. Two columns, up to three rows.
struct HomeTilesSection: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            SectionHeader(symbol: "square.grid.2x2.fill", tint: NotchColor.blue, title: "Tiles")
            // Up to three tiles are named buttons. More are icons, three across, with the name on hover.
            let compact = model.settings.homeTiles.count > 3
            LazyVGrid(
                columns: compact
                    ? Array(repeating: GridItem(.fixed(34 * s), spacing: 6 * s, alignment: .leading), count: 3)
                    : [GridItem(.flexible(), spacing: 6 * s, alignment: .leading)],
                alignment: .leading,
                spacing: 6 * s
            ) {
                ForEach(model.settings.homeTiles) { tile in
                    HomeTileButton(model: model, tile: tile, iconOnly: compact)
                }
            }
            .frame(maxWidth: compact ? nil : 190 * s, alignment: .leading)
        }
    }
}

/// App icons for app tiles, looked up once per app.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    /// The icon of the app at `path`. Nil when there is no app there.
    static func icon(forApp path: String) -> NSImage? {
        if let icon = icons[path] { return icon }
        guard !path.isEmpty, path.hasSuffix(".app"), FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        icons[path] = icon
        return icon
    }
}

/// A tile's picture: an app tile shows that app's own icon, the others a symbol.
struct HomeTileGlyph: View {
    let tile: HomeTile
    /// Replaces the tile's symbol, for a feature that is on right now.
    var symbol: String?
    var size: CGFloat

    var body: some View {
        if tile.kind == .app, let icon = AppIconCache.icon(forApp: tile.target) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol ?? tile.symbol)
                .font(.system(size: size * 0.8, weight: .semibold))
        }
    }
}

private struct HomeTileButton: View {
    let model: IslandModel
    let tile: HomeTile
    var iconOnly = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let isRunning = tile.kind == .shortcut && model.shortcuts.running.contains(tile.target)
        // A feature that's on right now (Keep Awake, a running timer) shows it, as in the launcher.
        let feature = tile.featureItem
        let isLive = feature.map(model.isLive) ?? false
        let symbol = feature.map { LauncherTile.symbol($0, live: isLive) } ?? tile.symbol
        Button {
            model.runTile(tile)
        } label: {
            HStack(spacing: 5 * s) {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    HomeTileGlyph(tile: tile, symbol: symbol, size: 15 * s)
                }
                if !iconOnly {
                    Text(tile.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: iconOnly ? .center : .leading)
        }
        .buttonStyle(TileChipStyle(scale: s, tint: isLive ? feature.map(LauncherTile.tint) ?? NotchColor.blue : NotchColor.blue))
        .disabled(isRunning)
        .help(tile.title)
        .accessibilityLabel(Text(tile.title))
    }
}

/// A tile's button: like the quick actions, but it takes the width of its column instead of its
/// own text, so a long name is cut off instead of overlapping the next tile.
private struct TileChipStyle: ButtonStyle {
    var scale: CGFloat
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        TileChip(configuration: configuration, scale: scale, tint: tint)
    }
}

private struct TileChip: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let tint: Color
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12 * scale, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9 * scale)
            .frame(maxWidth: .infinity, minHeight: 26 * scale, maxHeight: 26 * scale, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : (isHovering ? 0.14 : 0.09))))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// The tiles as one widget in the elongated row.
struct HomeTilesWidget: View {
    let model: IslandModel

    var body: some View {
        HomeTilesSection(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension IslandModel {
    /// Runs a tile: opens its app, website or folder, or runs its Shortcut. Anything that opens
    /// something closes the notch, like the launcher does.
    public func runTile(_ tile: HomeTile) {
        switch tile.kind {
        case .feature:
            guard let item = tile.featureItem, settings.isFeatureEnabled(item) else { return }
            open(item)
        case .app:
            let url = URL(fileURLWithPath: tile.target)
            guard url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            collapse()
        case .website:
            guard let url = tile.webURL else { return }
            NSWorkspace.shared.open(url)
            collapse()
        case .folder:
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: tile.target, isDirectory: &isDirectory), isDirectory.boolValue else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: tile.target, isDirectory: true))
            collapse()
        case .shortcut:
            shortcuts.run(tile.target)
        }
    }
}
