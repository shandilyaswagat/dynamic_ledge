import SwiftUI

// Stats: memory and CPU beside the camera, and a panel with memory, CPU, disk and network,
// styled like the small gauges in Activity Monitor and Control Center.

extension StatsMath.Level {
    var tint: Color {
        switch self {
        case .normal: NotchColor.green
        case .busy: NotchColor.yellow
        case .high: NotchColor.red
        }
    }
}

/// One side of the compact notch: a tiny caption over its value, like a watch complication.
struct StatsCompactValue: View {
    let caption: LocalizedStringKey
    let share: Double?
    /// Colour override (memory follows pressure, not percentage).
    var level: StatsMath.Level?
    let fontSize: CGFloat
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(caption)
                .font(.system(size: max(7, fontSize * 0.55), weight: .bold))
                .kerning(0.3)
                .foregroundStyle(NotchColor.secondaryText)
            Text(share.map(StatsMath.percent) ?? "–")
                .font(.system(size: fontSize * 0.9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(share.map { (level ?? StatsMath.level($0)).tint } ?? NotchColor.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Memory, CPU, disk and network, side by side.
struct StatsPanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let stats = model.stats
        let snapshot = stats.snapshot
        let ready = stats.hasReading
        HStack(spacing: 10 * s) {
            StatsTile(
                symbol: "memorychip", title: "Memory",
                value: snapshot.memoryTotal > 0 ? StatsMath.percent(snapshot.memory) : "–",
                detail: snapshot.memoryTotal > 0
                    ? "\(StatsMath.bytes(Int64(snapshot.memoryUsed))) of \(StatsMath.bytes(Int64(snapshot.memoryTotal)))"
                    : "",
                share: snapshot.memoryTotal > 0 ? snapshot.memory : nil,
                level: snapshot.memoryPressure
            )
            StatsTile(
                symbol: "cpu", title: "CPU",
                value: ready ? StatsMath.percent(snapshot.cpu) : "–",
                detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores",
                share: ready ? snapshot.cpu : nil
            )
            StatsTile(
                symbol: "internaldrive", title: "Disk",
                value: snapshot.diskTotal > 0 ? StatsMath.bytes(snapshot.diskFree) : "–",
                detail: snapshot.diskTotal > 0 ? "free of \(StatsMath.bytes(snapshot.diskTotal))" : "",
                share: snapshot.diskTotal > 0 ? snapshot.disk : nil
            )
            NetworkTile(snapshot: snapshot, ready: ready)
        }
        .padding(.bottom, 2 * s)
    }
}

private struct StatsTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    let detail: String
    /// Drives the bar and its colour; nil before the first reading.
    let share: Double?
    var level: StatsMath.Level?
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 4 * s)
            Text(value)
                .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 10 * s, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NotchColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6 * s)
            StatsBar(share: share, level: level)
                .frame(height: 4 * s)
        }
        .padding(10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(Color.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

private struct NetworkTile: View {
    let snapshot: SystemSnapshot
    let ready: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Network", systemImage: "network")
                .font(.system(size: 10.5 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
            Spacer(minLength: 4 * s)
            rate("arrow.down", ready ? StatsMath.rate(snapshot.networkIn) : "–", tint: NotchColor.blue)
            rate("arrow.up", ready ? StatsMath.rate(snapshot.networkOut) : "–", tint: NotchColor.orange)
            Spacer(minLength: 0)
        }
        .padding(10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(Color.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }

    private func rate(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 5 * s) {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 2 * s)
    }
}

/// A slim bar that fills and changes colour with the load.
struct StatsBar: View {
    let share: Double?
    var level: StatsMath.Level?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                if let share {
                    Capsule()
                        .fill((level ?? StatsMath.level(share)).tint)
                        .frame(width: max(geometry.size.height, geometry.size.width * share))
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: share)
        .accessibilityHidden(true)
    }
}

/// The Stats widget in the elongated Home: three bars in a column.
struct StatsWidget: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let snapshot = model.stats.snapshot
        let ready = model.stats.hasReading
        Button { model.showTab(.stats) } label: {
            VStack(alignment: .leading, spacing: 8 * s) {
                row("Memory", value: snapshot.memoryTotal > 0 ? StatsMath.percent(snapshot.memory) : "–", share: snapshot.memoryTotal > 0 ? snapshot.memory : nil, level: snapshot.memoryPressure)
                row("CPU", value: ready ? StatsMath.percent(snapshot.cpu) : "–", share: ready ? snapshot.cpu : nil)
                HStack(spacing: 10 * s) {
                    Label(ready ? StatsMath.rate(snapshot.networkIn) : "–", systemImage: "arrow.down")
                    Label(ready ? StatsMath.rate(snapshot.networkOut) : "–", systemImage: "arrow.up")
                }
                .font(.system(size: 10.5 * s, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(NotchColor.secondaryText)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help("Open Stats")
    }

    private func row(_ title: LocalizedStringKey, value: String, share: Double?, level: StatsMath.Level? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack {
                Text(title)
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundStyle(NotchColor.secondaryText)
                Spacer(minLength: 6 * s)
                Text(value)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            StatsBar(share: share, level: level)
                .frame(height: 4 * s)
        }
    }
}
