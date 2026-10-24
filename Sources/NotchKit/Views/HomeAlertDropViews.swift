import SwiftUI
import UniformTypeIdentifiers

// MARK: Alerts

struct AlertView: View {
    let model: IslandModel
    let alert: IslandAlert
    /// Middle width kept clear for the camera in notch style.
    var cameraGap: CGFloat = 0
    @Environment(\.notchScale) private var s

    var body: some View {
        switch alert {
        case .charging(let level, let isCharging):
            let lowPower = model.power.snapshot?.isLowPowerMode == true
            let tint = lowPower ? NotchColor.yellow : NotchColor.green
            AlertRow(cameraGap: cameraGap) {
                Text(isCharging ? "Charging" : "Connected")
            } trailing: {
                BatteryLabel(level: level, isCharging: true, tint: tint)
            }
            .accessibilityElement(children: .combine)
        case .lowBattery(let level):
            AlertRow(cameraGap: cameraGap) {
                Text("Low Battery")
            } trailing: {
                BatteryLabel(level: level, isCharging: false, tint: NotchColor.red)
            }
            .accessibilityElement(children: .combine)
        case .headphones(let name, let symbol):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: symbol)
                        .font(.system(size: 15 * s, weight: .medium))
                    Text(name)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                Text("Connected")
                    .foregroundStyle(NotchColor.green)
            }
            .accessibilityElement(children: .combine)
        case .timerFinished:
            TimerFinishedView(model: model)
        case .welcome:
            AlertRow(cameraGap: cameraGap) {
                Text(Greeting.text(fullName: NSFullUserName()))
                    .truncationMode(.tail)
            } trailing: {
                WavingHand()
            }
            .accessibilityElement(children: .combine)
        case .level(let kind, let value, let muted):
            AlertRow(cameraGap: cameraGap) {
                Image(systemName: Self.levelSymbol(kind, value: value, muted: muted))
                    .font(.system(size: 15 * s, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24 * s, alignment: .leading)
            } trailing: {
                LevelBar(value: muted ? 0 : value)
                    .frame(width: 64 * s, height: 6 * s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(kind == .volume ? "Volume" : "Brightness"))
            .accessibilityValue(Text(muted ? "Muted" : "\(Int((value * 100).rounded())) percent"))
        case .upcomingEvent(let title, let minutes):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: "calendar")
                        .foregroundStyle(NotchColor.red)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                Text(minutes <= 0 ? "Starting now" : "In \(minutes) min")
                    .foregroundStyle(NotchColor.red)
            }
            .accessibilityElement(children: .combine)
        case .download(let url):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20 * s, height: 20 * s)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // Drag the file straight out of the notch.
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            } trailing: {
                Text("Downloaded")
                    .foregroundStyle(NotchColor.blue)
            }
            .help("Click to show in Finder, or drag it out")
            .accessibilityElement(children: .combine)
        case .updateAvailable(let version):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(NotchColor.blue)
                    Text("Update")
                }
            } trailing: {
                Text("Version \(version)")
                    .foregroundStyle(NotchColor.blue)
            }
            .help("Click to see what's new and install it")
            .accessibilityElement(children: .combine)
        case .shortcut(let name, let succeeded):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(NotchColor.blue)
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                Text(succeeded ? "Done" : "Failed")
                    .foregroundStyle(succeeded ? NotchColor.green : NotchColor.red)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static func levelSymbol(_ kind: IslandAlert.LevelKind, value: Double, muted: Bool) -> String {
        switch kind {
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

/// Leading content left of the camera, trailing content right of it.
private struct AlertRow<Leading: View, Trailing: View>: View {
    var cameraGap: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.notchScale) private var s

    var body: some View {
        GeometryReader { geometry in
            let edge: CGFloat = (cameraGap > 0 ? 14 : 20) * s
            let side = max(0, (geometry.size.width - cameraGap) / 2 - edge - (cameraGap > 0 ? 6 : 4))
            HStack(spacing: 0) {
                leading
                    .frame(width: side, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, edge)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .font(.system(size: 14 * s, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
}

private struct BatteryLabel: View {
    var level: Int
    var isCharging: Bool
    var tint: Color
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Text("\(level)%")
                .monospacedDigit()
                .foregroundStyle(tint)
            BatteryGlyph(level: level, isCharging: isCharging, color: tint, width: 27 * s)
        }
    }
}

/// A hand that waves from the wrist while the hello shows.
private struct WavingHand: View {
    @Environment(\.notchScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "\u{1F44B}")
            .font(.system(size: 17 * s))
            .phaseAnimator(reduceMotion ? [0.0] : [0.0, 20, -8, 20, -8, 14, 0, 0, 0]) { hand, angle in
                hand.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.7, y: 0.85))
            } animation: { _ in
                .easeInOut(duration: 0.16)
            }
            .accessibilityHidden(true)
    }
}

private struct TimerFinishedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    private static func headline(_ mode: TimerMode) -> LocalizedStringKey {
        switch mode {
        case .plain: "Done"
        case .focus: "Take a break"
        case .rest: "Back to it"
        }
    }

    var body: some View {
        let mode = model.timer.timer?.mode ?? .plain
        HStack(spacing: 12 * s) {
            Image(systemName: "bell.fill")
                .font(.system(size: 24 * s, weight: .semibold))
                .foregroundStyle(mode.tint)
                .phaseAnimator([0.0, -16, 14, -10, 8, 0, 0, 0]) { bell, angle in
                    bell.rotationEffect(.degrees(angle), anchor: .top)
                } animation: { _ in
                    .easeInOut(duration: 0.11)
                }
                .frame(width: 44 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(mode.title)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(mode.tint)
                Text(Self.headline(mode))
                    .font(.system(size: 26 * s, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8 * s)
            if let next = mode.next {
                // Focus offers the break, and the break offers the next focus session.
                CircleButton(symbol: next.symbol, size: 48 * s, foreground: next.tint, background: next.tint.opacity(0.25), label: next == .rest ? "Start Break" : "Focus Again") {
                    model.startSession(next)
                }
            } else {
                CircleButton(symbol: "arrow.counterclockwise", size: 48 * s, label: "Repeat Timer") { model.repeatTimer() }
            }
            CircleButton(symbol: "xmark", size: 48 * s, foreground: .black, background: mode.tint, label: "Stop Timer") {
                model.stopTimerAlarm()
            }
        }
        .padding(.horizontal, 20 * s)
    }
}

// MARK: Drop

struct DropView: View {
    let model: IslandModel
    let isTargeted: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            if model.settings.trayEnabled {
                zone(.tray, title: "Tray", targetedTitle: "Keep in Tray", symbol: "tray.and.arrow.down.fill", tint: .white)
            }
            if model.settings.airDropEnabled {
                zone(.airDrop, title: "AirDrop", targetedTitle: "Send with AirDrop", symbol: "dot.radiowaves.up.forward", tint: NotchColor.blue)
            }
        }
        .padding(12 * s)
    }

    private func zone(_ zone: IslandModel.DropZone, title: LocalizedStringKey, targetedTitle: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        let targeted = model.targetedZone == zone
        return ZStack {
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .fill(tint.opacity(targeted ? 0.16 : 0.05))
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .strokeBorder(tint.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            VStack(spacing: 8 * s) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(targeted ? 0.3 : 0.15))
                        .frame(width: 40 * s, height: 40 * s)
                    Image(systemName: symbol)
                        .font(.system(size: 17 * s, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .scaleEffect(targeted ? 1.1 : 1)
                Text(targeted ? targetedTitle : title)
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: targeted)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url], isTargeted: Binding(
            get: { model.targetedZone == zone },
            set: { model.setTargeted(zone, $0) }
        )) { providers in
            loadURLs(from: providers, into: zone)
            return true
        }
        .accessibilityElement(children: .combine)
    }

    private func loadURLs(from providers: [NSItemProvider], into zone: IslandModel.DropZone) {
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                // A document proxy may arrive as `public.url`. Only local file URLs are valid
                // tray or AirDrop inputs; reject web and custom-scheme URLs.
                if let url, url.isFileURL { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                switch zone {
                case .tray: model.addToTray(collector.urls)
                case .airDrop: model.airDrop(collector.urls)
                }
            }
        }
    }
}

/// Collects URLs from item-provider callbacks, which arrive on background threads.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Thin level meter for volume and brightness.
private struct LevelBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0), value: value)
    }
}
