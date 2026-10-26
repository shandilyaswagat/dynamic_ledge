#if DEBUG
import AppKit

/// Debug builds only: drive the pill from the command line for QA screenshots.
///
///     osascript -l JavaScript -e 'ObjC.import("Foundation");
///       $.NSDistributedNotificationCenter.defaultCenter
///         .postNotificationNameObjectUserInfoDeliverImmediately("DynamicNotch.debug", "charging", $(), true)'
@MainActor
final class DebugHooks {
    private let model: IslandModel
    private let settings: SettingsWindowController
    private var observer: NSObjectProtocol?

    init(model: IslandModel, settings: SettingsWindowController) {
        self.model = model
        self.settings = settings
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("DynamicNotch.debug"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let command = notification.object as? String ?? ""
            MainActor.assumeIsolated { self?.run(command) }
        }
    }

    private func run(_ command: String) {
        let parts = command.split(separator: ":").map(String.init)
        switch parts.first {
        case "charging": model.receive(.charging(level: 82, isCharging: true))
        case "lowbattery": model.receive(.lowBattery(level: 20))
        case "headphones": model.receive(.headphones(name: "AirPods Pro", symbol: "airpodspro"))
        case "timer": model.startTimer(Double(parts.dropFirst().first ?? "") ?? 300)
        case "pause": model.timer.togglePause()
        case "cancel": model.cancelTimer()
        case "home": model.expand(.home)
        case "expand": if case .compact(let primary, _) = model.presentation { model.expand(.activity(primary)) }
        case "collapse": model.collapse()
        case "drop": model.fileDragChanged(isDragging: true, at: CGPoint(x: model.engine.anchorX, y: 10))
        case "target": model.isDropTargeted = true
        case "nodrop": model.fileDragChanged(isDragging: false, at: nil)
        case "peek": model.pointerMoved(to: CGPoint(x: model.engine.notchInWindow.midX, y: 10))
        case "unhover": model.pointerMoved(to: nil)
        case "hover": model.pointerMoved(to: CGPoint(x: model.layout.pill.midX, y: model.layout.pill.midY))
        case "swipe": model.cyclePrimary(forward: true)
        case "settings": settings.show(parts.dropFirst().first.flatMap(Int.init).flatMap(SettingsWindowController.Tab.init(rawValue:)))
        case "idle": model.settings.showWhenIdle.toggle()
        case "dismiss": model.dismissAlert()
        case "size": model.settings.appearance.size = parts.dropFirst().first.flatMap(NotchSize.init(rawValue:)) ?? .large
        case "welcome": model.receive(.welcome)
        case "tray": model.showTab(.tray)
        case "mirror": model.showTab(.mirror)
        case "clipboard": model.showTab(.clipboard)
        case "timers": model.timerPanelMode = parts.dropFirst().first.flatMap(TimerPanelMode.init(rawValue:)) ?? .timer; model.showTab(.timers)
        case "calendar": model.showTab(.calendar)
        case "launcher": model.showTab(.launcher)
        case "hoverexpand": model.settings.notchOpenMode = parts.dropFirst().first != "off" ? .hover : .click
        case "reminders": model.showTab(.reminders)
        case "checkupdate": model.updater.check()
        case "fakeupdate":
            let base = "https://github.com/shandilyaswagat/dynamic_notch/releases"
            model.updater.simulateAvailable(ReleaseInfo(version: SemanticVersion("9.9.9")!, diskImage: URL(string: base + "/download/v9.9.9/DynamicNotch.dmg")!, checksum: nil, signedManifest: URL(string: base + "/download/v9.9.9/DynamicNotch.update.json")!, page: URL(string: base)!))
        case "stopwatch": model.stopwatch.start()
        case "awake": model.keepAwake.toggle()
        case "download": model.receive(.download(URL(fileURLWithPath: parts.dropFirst().first ?? "/tmp/Report.pdf")))
        case "expandnow": if case .compact(let primary, _) = model.presentation { model.expand(.activity(primary)) }
        case "skip": model.swipe(forward: true)
        case "notes": model.showTab(.notes)
        case "focus": if let seconds = parts.dropFirst().first.flatMap(Double.init) { model.timer.start(duration: seconds, mode: .focus) } else { model.startSession(.focus) }
        case "break": model.startSession(.rest)
        case "trayadd": model.addToTray(parts.dropFirst().map { URL(fileURLWithPath: $0) })
        case "volume": model.receive(.level(.volume, value: Double(parts.dropFirst().first ?? "") ?? 0.6, muted: false))
        case "brightness": model.receive(.level(.brightness, value: Double(parts.dropFirst().first ?? "") ?? 0.4, muted: false))
        case "event": model.receive(.upcomingEvent(title: "Design review", minutes: 5))
        case "shortcutdone": model.receive(.shortcut(name: "Morning Routine", succeeded: true))
        case "dump":
            let info = model.nowPlaying.info
            let line = "presentation=\(model.presentation) active=\(model.activeActivities.map(\.rawValue).sorted()) "
                + "playing=\(String(describing: info?.isPlaying)) lingering=\(model.nowPlaying.isLingering) "
                + "title=\(info?.title ?? "-") rate=\(info?.playbackRate ?? -1) expand=\(String(describing: model.expandTarget)) "
                + "hoverNotch=\(model.isHoveringNotch) hoverPill=\(model.isHoveringPill) notch=\(model.engine.notchInWindow) virtual=\(model.engine.isVirtualNotch)\n"
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DynamicNotch-debug.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        default: break
        }
    }
}
#endif
