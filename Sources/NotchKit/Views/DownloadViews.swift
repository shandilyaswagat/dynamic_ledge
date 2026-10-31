import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Downloads use the system blue, like Safari's download button.
private let downloadTint = NotchColor.blue

/// Left of the camera in the compact notch.
struct DownloadCompactIcon: View {
    let fontSize: CGFloat

    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: fontSize + 1, weight: .semibold))
            .foregroundStyle(downloadTint)
            .accessibilityLabel(Text("Downloading"))
    }
}

/// Right of the camera: how far along, or how much has arrived when the size isn't known.
struct DownloadCompactValue: View {
    let summary: DownloadSummary
    let fontSize: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(downloadTint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }

    private var label: String {
        if let fraction = summary.fraction { return "\(Int((fraction * 100).rounded(.down)))%" }
        let bytes = summary.items.reduce(Int64(0)) { $0 + $1.completed }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// A ring that fills as the download arrives; it spins when the size isn't known.
struct DownloadRing: View {
    let fraction: Double?
    let diameter: CGFloat

    var body: some View {
        let line = max(2, diameter * 0.12)
        ZStack {
            Circle().stroke(downloadTint.opacity(0.25), lineWidth: line)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(downloadTint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.4), value: fraction)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(downloadTint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            }
            Image(systemName: "arrow.down")
                .font(.system(size: diameter * 0.38, weight: .bold))
                .foregroundStyle(downloadTint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(Text("Downloading"))
        .accessibilityValue(Text(fraction.map { "\(Int($0 * 100)) percent" } ?? ""))
    }
}

/// The open notch: the file, a bar, how much is left, and buttons to find or stop it.
struct DownloadExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let summary = model.downloadProgress.summary
        if let item = summary.items.first {
            HStack(spacing: 12 * s) {
                Image(nsImage: Self.icon(for: item.name))
                    .resizable()
                    .frame(width: 40 * s, height: 40 * s)
                VStack(alignment: .leading, spacing: 6 * s) {
                    HStack(spacing: 6 * s) {
                        Text(item.name)
                            .font(.system(size: 13 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if summary.items.count > 1 {
                            Text("+\(summary.items.count - 1) more")
                                .font(.system(size: 11 * s, weight: .medium))
                                .foregroundStyle(NotchColor.secondaryText)
                                .fixedSize()
                        }
                    }
                    ProgressBar(fraction: item.fraction)
                        .frame(height: 5 * s)
                    Text(detail(item))
                        .font(.system(size: 11 * s, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(NotchColor.secondaryText)
                        .lineLimit(1)
                }
                CircleButton(symbol: "magnifyingglass", size: 34 * s, label: "Show in Finder") {
                    model.downloadProgress.reveal(item.id)
                }
                if model.downloadProgress.canCancel(item.id) {
                    CircleButton(symbol: "xmark", size: 34 * s, label: "Stop Download") {
                        model.downloadProgress.cancel(item.id)
                    }
                }
            }
            .padding(.horizontal, 20 * s)
        }
    }

    private func detail(_ item: DownloadProgressItem) -> String {
        let bytes = DownloadFormat.bytes(item.completed, of: item.total)
        guard let left = item.secondsLeft else { return bytes }
        return bytes + " · " + DownloadFormat.timeLeft(left)
    }

    /// The icon Finder would show for the finished file.
    private static func icon(for name: String) -> NSImage {
        let ext = (name as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

private struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                if let fraction {
                    Capsule()
                        .fill(downloadTint)
                        .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                        .animation(.smooth(duration: 0.4), value: fraction)
                } else {
                    // Size unknown: a short segment sweeps across.
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule()
                            .fill(downloadTint)
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: (proxy.size.width * 1.3) * phase - proxy.size.width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .accessibilityHidden(true)
    }
}
