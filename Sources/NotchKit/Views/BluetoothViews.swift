import SwiftUI

struct BluetoothPanelBody: View {
    var compact = false
    @Environment(\.notchScale) private var s
    @State private var snapshot: BluetoothBatterySnapshot?

    var body: some View {
        Group {
            switch snapshot {
            case nil:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Reading Bluetooth devices"))
            case .unavailable:
                emptyState("Couldn’t read Bluetooth devices")
            case .poweredOff:
                emptyState("Bluetooth is off")
            case .connected(let devices):
                if devices.isEmpty {
                    emptyState("No connected Bluetooth devices")
                } else {
                    ScrollView {
                        VStack(spacing: (compact ? 3 : 5) * s) {
                            ForEach(devices.indices, id: \.self) { index in
                                if compact {
                                    compactRow(devices[index])
                                } else {
                                    deviceRow(devices[index])
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8 * s)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                let reading = await BluetoothBatteryReader.read()
                guard !Task.isCancelled else { return }
                snapshot = reading
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
            }
        }
    }

    private func compactRow(_ device: BluetoothBatteryDevice) -> some View {
        let name = device.name.isEmpty ? Text("Unnamed device") : Text(device.name)
        let earpieces = [device.left, device.right].compactMap { $0 }
        return HStack(spacing: 4 * s) {
            name
                .font(.system(size: 11 * s, weight: .medium))
                .lineLimit(1)
                .help(name)
            Spacer(minLength: 0)
            if let main = device.main {
                batteryLevel(main, showsIcon: false)
            } else if let lowest = earpieces.min() {
                batteryLevel(lowest, label: "Earbuds", showsIcon: false)
            } else if let chargingCase = device.chargingCase {
                batteryLevel(chargingCase, label: "Case", showsIcon: false)
            } else {
                batteryLevel(nil, showsIcon: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyState(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12 * s, weight: .medium))
            .foregroundStyle(NotchColor.secondaryText)
    }

    private func deviceRow(_ device: BluetoothBatteryDevice) -> some View {
        let name = device.name.isEmpty ? Text("Unnamed device") : Text(device.name)
        return HStack(spacing: 10 * s) {
            Image(systemName: device.kind.symbol(for: device.name))
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundStyle(NotchColor.blue)
                .frame(width: 32 * s, height: 32 * s)
                .background(NotchColor.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9 * s))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3 * s) {
                name
                    .font(.system(size: 13 * s, weight: .semibold))
                    .lineLimit(1)
                    .help(name)
                Text(device.kind.title)
                    .font(.system(size: 10 * s))
                    .foregroundStyle(NotchColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if device.left != nil || device.right != nil || device.chargingCase != nil {
                if let level = device.main { batteryLevel(level, label: "Main") }
                batteryLevel(device.left, label: "Left")
                batteryLevel(device.right, label: "Right")
                batteryLevel(device.chargingCase, label: "Case")
            } else if let level = device.main {
                batteryLevel(level)
            } else {
                Text("Battery unavailable")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 7 * s)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10 * s))
        .accessibilityElement(children: .combine)
    }

    private func batteryLevel(_ level: Int?, label: LocalizedStringKey? = nil, showsIcon: Bool = true) -> some View {
        VStack(alignment: .trailing, spacing: 3 * s) {
            if let level {
                HStack(spacing: 5 * s) {
                    if showsIcon {
                        Image(systemName: batterySymbol(at: level))
                            .font(.system(size: 15 * s, weight: .medium))
                            .accessibilityHidden(true)
                    }
                    Text(Double(level) / 100, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13 * s, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(batteryColor(at: level))
            } else {
                Text("—")
                    .font(.system(size: 13 * s))
                    .foregroundStyle(NotchColor.secondaryText)
                    .accessibilityLabel(Text("Battery unavailable"))
            }
            if let label {
                Text(label)
                    .font(.system(size: 10 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
        .fixedSize()
    }

    private func batteryColor(at level: Int) -> Color {
        switch level {
        case 80...: NotchColor.green
        case 30...: NotchColor.yellow
        default: NotchColor.red
        }
    }

    private func batterySymbol(at level: Int) -> String {
        switch level {
        case 90...: "battery.100percent"
        case 65...: "battery.75percent"
        case 40...: "battery.50percent"
        case 1...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}

private extension BluetoothDeviceKind {
    var title: LocalizedStringKey {
        switch self {
        case .headphones: "Headphones"
        case .speaker: "Speaker"
        case .mouse: "Mouse"
        case .trackpad: "Trackpad"
        case .keyboard: "Keyboard"
        case .controller: "Game Controller"
        case .microphone: "Microphone"
        case .other: "Bluetooth Device"
        }
    }

    func symbol(for name: String) -> String {
        switch self {
        case .headphones: HeadphoneSymbol.symbol(forDeviceName: name)
        case .speaker: "hifispeaker"
        case .mouse: "computermouse"
        case .trackpad: "trackpad"
        case .keyboard: "keyboard"
        case .controller: "gamecontroller"
        case .microphone: "mic"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}
