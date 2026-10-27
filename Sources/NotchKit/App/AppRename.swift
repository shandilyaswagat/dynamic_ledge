import AppKit
import ServiceManagement
import os

/// From 1.4.0 the app is called Dynamic Ledge. Updating from 1.3.x swaps the new version into
/// the old "Dynamic Notch.app" in place, so on its first launch the app gives its own file the
/// new name and reopens from there. Homebrew copies update the same way (the cask is marked as
/// updating itself), and the renamed cask expects "Dynamic Ledge.app" too.
enum AppRename {
    static let oldName = "Dynamic Notch.app"
    static let newName = "Dynamic Ledge.app"

    /// Where the app should live now, or nil to leave it where it is: already renamed, run from
    /// a disk image or a read-only folder, or the new name is taken.
    nonisolated static func destination(for bundle: URL, fileManager: FileManager = .default) -> URL? {
        guard bundle.lastPathComponent == oldName, Updater.canReplace(bundle) else { return nil }
        let target = bundle.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fileManager.fileExists(atPath: target.path) else { return nil }
        return target
    }

    private static let renamedKey = "app.renamedToLedge"

    /// After the rename, Open at Login is registered again from the app's new location.
    @MainActor
    static func finishIfRenamed() {
        guard UserDefaults.standard.bool(forKey: renamedKey) else { return }
        UserDefaults.standard.removeObject(forKey: renamedKey)
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
    }

    /// Renames the app and reopens it under the new name. Returns true when this copy is about
    /// to quit for that, so launch should stop here.
    @MainActor
    static func renameAndRelaunchIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard let target = destination(for: bundle) else { return false }
        let log = Logger(subsystem: Log.subsystem, category: "app")
        do {
            try FileManager.default.moveItem(at: bundle, to: target)
        } catch {
            log.error("Couldn't rename the app: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // The reopened copy points Open at Login at the new location (see `finishIfRenamed`).
        UserDefaults.standard.set(true, forKey: renamedKey)
        // The helper library copy moved to a folder with the new name too.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("Dynamic Notch", isDirectory: true))
        }
        log.notice("Renamed the app to \(newName, privacy: .public); reopening")
        // Reopen once this copy has quit, the same way an update relaunches.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                             "sh", String(ProcessInfo.processInfo.processIdentifier), target.path]
        do {
            try process.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
