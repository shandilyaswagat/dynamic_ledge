import Charts
import SwiftUI

enum StatsColor {
    static let cpu = Color.accentColor
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let network = Color(nsColor: .systemBlue)

    static func battery(_ battery: PowerSnapshot) -> Color {
        if battery.isCharging { return Color(nsColor: .systemGreen) }
        if !battery.isOnAC, let low = PowerTransitions.lowBatteryThresholds.first, battery.level <= low {
            return Color(nsColor: .systemRed)
        }
        return Color(nsColor: battery.isLowPowerMode ? .systemYellow : .systemGreen)
    }

    static func pressure(_ level: StatsMath.Level) -> Color {
        switch level {
        case .normal: Color(nsColor: .systemGreen)
        case .busy: Color(nsColor: .systemYellow)
        case .high: Color(nsColor: .systemRed)
        }
    }
}

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

/// The selected Stats panel uses the nook surface and its existing toolbar.
struct StatsPanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let stats = model.stats
        let gap = 14 * s
        GeometryReader { geometry in
            HStack(spacing: gap) {
                StatsCPUChart(
                    usage: stats.hasReading ? stats.snapshot.cpu : nil,
                    history: stats.cpuHistory
                )
                .frame(width: max(0, (geometry.size.width - gap) * 0.52))

                readings(stats)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 2 * s)
        .accessibilityIdentifier("stats-panel")
    }

    private func readings(_ stats: StatsService) -> some View {
        let snapshot = stats.snapshot
        let pressure = stats.panelMemoryPressure.map(StatsColor.pressure)
        return VStack(spacing: 0) {
            row("Memory", symbol: "memorychip", value: memoryValue(snapshot),
                detail: pressureLabel(stats.panelMemoryPressure), indicator: pressure, symbolTint: pressure)
            Divider()
            row("Network", symbol: "network", value: networkValue(snapshot, ready: stats.hasNetworkReading),
                symbolTint: StatsColor.network)
            if let battery = model.power.snapshot, battery.hasBattery {
                let tint = StatsColor.battery(battery)
                Divider()
                row("Battery", symbol: batterySymbol(battery),
                    value: Text("\(battery.level.formatted(.percent.scale(1)))").foregroundColor(tint),
                    detail: batteryDetail(battery), symbolTint: tint)
            }
            Divider()
            row("Storage", symbol: "internaldrive", value: snapshot.diskTotal > 0
                ? Text("\(StatsMath.bytes(snapshot.diskFree)) available") : Text("–"),
                symbolTint: .accentColor, usedCapacity: snapshot.diskTotal > 0 ? snapshot.disk : nil)
        }
    }

    private func memoryValue(_ snapshot: SystemSnapshot) -> Text {
        guard snapshot.memoryTotal > 0 else { return Text("–") }
        return Text("\(StatsMath.bytes(Int64(snapshot.memoryUsed))) of \(StatsMath.bytes(Int64(snapshot.memoryTotal)))")
    }

    private func pressureLabel(_ pressure: StatsMath.Level?) -> Text? {
        switch pressure {
        case .normal: Text("Pressure: Normal")
        case .busy: Text("Pressure: Warning")
        case .high: Text("Pressure: Critical")
        case nil: nil
        }
    }

    private func networkValue(_ snapshot: SystemSnapshot, ready: Bool) -> Text {
        guard ready else { return Text("–") }
        let download = StatsMath.rate(snapshot.networkIn)
        let upload = StatsMath.rate(snapshot.networkOut)
        let down = Text(Image(systemName: "arrow.down")).foregroundColor(StatsColor.network)
        let up = Text(Image(systemName: "arrow.up")).foregroundColor(StatsColor.network)
        return Text("\(down) \(download)    \(up) \(upload)")
            .accessibilityLabel(Text("Download \(download), upload \(upload)"))
    }

    private func batterySymbol(_ battery: PowerSnapshot) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        let fill = Int((Double(battery.level) / 25).rounded()) * 25
        return "battery.\(fill)percent"
    }

    private func batteryDetail(_ battery: PowerSnapshot) -> Text {
        if let minutes = battery.estimatedMinutes {
            let duration = TimeFormatting.presetLabel(seconds: Double(minutes) * 60)
            return battery.isCharging ? Text("About \(duration) until full") : Text("About \(duration) remaining")
        }
        if battery.isCharging { return Text("Charging") }
        if battery.isOnAC { return Text("Power Adapter") }
        return Text("On Battery")
    }

    private func row(
        _ title: LocalizedStringKey, symbol: String, value: Text, detail: Text? = nil,
        indicator: Color? = nil, symbolTint: Color? = nil, usedCapacity: Double? = nil
    ) -> some View {
        HStack(spacing: 7 * s) {
            Image(systemName: symbol)
                .font(.system(size: 14 * s, weight: .medium))
                .foregroundStyle(symbolTint ?? Color(nsColor: .secondaryLabelColor))
                .frame(width: 18 * s)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3 * s) {
                Text(title)
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detail {
                    HStack(spacing: 4 * s) {
                        if let indicator {
                            Circle()
                                .fill(indicator)
                                .frame(width: 5 * s, height: 5 * s)
                                .accessibilityHidden(true)
                        }
                        detail
                            .font(.system(size: 10.5 * s))
                            .foregroundStyle(indicator ?? Color(nsColor: .secondaryLabelColor))
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3 * s) {
                value
                    .font(.system(size: 12 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let usedCapacity {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: geometry.size.width * usedCapacity)
                            }
                    }
                    .frame(width: 80 * s, height: 4 * s)
                    .accessibilityRepresentation {
                        ProgressView(value: usedCapacity)
                            .accessibilityLabel(Text("Share of capacity unavailable"))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct StatsCPUChart: View {
    let usage: Double?
    let history: [Double]
    @Environment(\.notchScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let historyDuration = Double(StatsService.cpuHistoryLimit) * StatsService.interval

    var body: some View {
        let reading = usage.map(StatsMath.percent) ?? "–"
        let shape = RoundedRectangle(cornerRadius: 14 * s, style: .continuous)

        VStack(alignment: .leading, spacing: 6 * s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                Text("CPU Usage")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(reading)
                    .font(.system(size: 28 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(usage == nil ? HierarchicalShapeStyle.secondary : .primary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: reading)
            }
            .accessibilityElement(children: .combine)

            chart
                .frame(maxHeight: .infinity)
        }
        .padding(12 * s)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(StatsColor.surface, in: shape)
        .overlay { shape.strokeBorder(StatsColor.separator, lineWidth: 0.5).allowsHitTesting(false) }
    }

    private var chart: some View {
        Chart {
            ForEach(history.indices, id: \.self) { index in
                let seconds = Double(index + 1 - history.count) * StatsService.interval
                let percent = history[index] * 100
                AreaMark(x: .value("Seconds from latest sample", seconds), y: .value("CPU usage", percent))
                    .foregroundStyle(.linearGradient(
                        colors: [StatsColor.cpu.opacity(0.22), StatsColor.cpu.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .accessibilityHidden(true)
                LineMark(x: .value("Seconds from latest sample", seconds), y: .value("CPU usage", percent))
                    .foregroundStyle(StatsColor.cpu)
                    .lineStyle(StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, lineJoin: .round))
                    .accessibilityValue(Text(history[index].formatted(.percent.precision(.fractionLength(0)))))
            }

            if let latest = history.last {
                PointMark(x: .value("Seconds from latest sample", 0.0), y: .value("CPU usage", latest * 100))
                    .foregroundStyle(StatsColor.cpu)
                    .symbolSize(17 * s * s)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: -Self.historyDuration...0,
                     range: .plotDimension(startPadding: 0, endPadding: 3 * s))
        .chartYScale(domain: 0.0...100.0,
                     range: .plotDimension(startPadding: 3 * s, endPadding: 3 * s))
        .chartXAxis {
            AxisMarks(values: [-Self.historyDuration]) { _ in
                AxisValueLabel(anchor: .topLeading) {
                    axisLabel("60s ago")
                }
            }
            AxisMarks(values: [0.0]) { _ in
                AxisValueLabel(anchor: .topTrailing) {
                    axisLabel("Now")
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(StatsColor.separator)
                if let percent = value.as(Double.self) {
                    AxisValueLabel {
                        axisLabel("\(percent.formatted(.percent.scale(1)))")
                    }
                }
            }
        }
        .accessibilityLabel(Text("CPU usage over the last minute"))
    }

    private func axisLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10 * s))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
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
