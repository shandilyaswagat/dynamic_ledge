import AppKit
@preconcurrency import ApplicationServices

/// Captures one window at mouse-down. Resolution never falls back to another window or app.
@MainActor
final class DocumentWindowDrag {
    struct Resolution: Sendable {
        var url: URL?
        var message: String?
    }

    private var window: AXUIElement?
    private var origin: CGPoint?
    private var movementConfirmed = false

    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func begin(at point: CGPoint) -> Bool {
        reset()
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return false }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(primary.frame.maxY - point.y), &hit) == .success,
              let hit else { return false }
        var candidate = hit
        if let owner = attribute(hit, kAXWindowAttribute), CFGetTypeID(owner) == AXUIElementGetTypeID() {
            candidate = unsafeDowncast(owner, to: AXUIElement.self)
        }
        for _ in 0..<8 {
            if attribute(candidate, kAXRoleAttribute) as? String == kAXWindowRole {
                AXUIElementSetMessagingTimeout(candidate, 0.05)
                guard let position = position(candidate) else { return false }
                window = candidate
                origin = position
                return true
            }
            guard let parent = attribute(candidate, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            candidate = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }

    var hasMoved: Bool {
        if movementConfirmed { return true }
        guard let window, let origin, let current = position(window) else { return false }
        movementConfirmed = DocumentDragPolicy.hasMoved(from: origin, to: current)
        return movementConfirmed
    }

    func reset() {
        window = nil
        origin = nil
        movementConfirmed = false
    }

    func resolve() async -> Resolution {
        guard hasMoved, let window else { return Resolution() }
        for key in [kAXDocumentAttribute, "AXURL", "AXDocumentURL", "AXFilename"] {
            if let value = attribute(window, key) {
                let url = (value as? URL) ?? (value as? String).flatMap(Self.localURL)
                if let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                    return Resolution(url: url)
                }
            }
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              let title = attribute(window, kAXTitleAttribute) as? String, !title.isEmpty else {
            return Resolution(message: "This window does not expose a saved document.")
        }
        return await Task.detached(priority: .userInitiated) {
            Self.resolveScript(identifier: identifier, title: title)
        }.value
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func position(_ element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private nonisolated static func localURL(_ text: String) -> URL? {
        if let url = URL(string: text), url.isFileURL { return url }
        guard text.hasPrefix("/") || text.hasPrefix("~") else { return nil }
        return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
    }

    private nonisolated static func resolveScript(identifier: String, title: String) -> Resolution {
        let chromium = ["com.brave.Browser", "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"]
        let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        let editors = ["com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote", "com.apple.TextEdit"]
        guard chromium.contains(identifier) || safari.contains(identifier) || editors.contains(identifier) else {
            return Resolution(message: "This app does not expose the saved document location for this window.")
        }
        // Pass the title as argv, never interpolate untrusted window titles into script code.
        let lookup: String
        if chromium.contains(identifier) {
            lookup = "return URL of active tab of targetWindow"
        } else if safari.contains(identifier) {
            lookup = "return URL of current tab of targetWindow"
        } else {
            lookup = """
            try
                return POSIX path of ((file of document of targetWindow) as alias)
            on error
                return POSIX path of ((path of document of targetWindow) as alias)
            end try
            """
        }
        let script = """
        on run argv
            with timeout of 3 seconds
                tell application id "\(identifier)"
                    set matches to every window whose name is (item 1 of argv)
                    if (count matches) is not 1 then error "Window is missing or ambiguous"
                    set targetWindow to item 1 of matches
                    \(lookup)
                end tell
            end timeout
        end run
        """
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, title]
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let pid = process.processIdentifier
            let deadline = DispatchWorkItem { _ = kill(pid, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: deadline)
            defer { deadline.cancel() }
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                return Resolution(message: "Could not read this open document. Enable Dynamic Notch access to the document app in macOS Automation settings, then try again.")
            }
            let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = localURL(value), FileManager.default.fileExists(atPath: url.path) { return Resolution(url: url) }
            if let url = URL(string: value), DropPolicy.isSupported(url) { return Resolution(url: url) }
        } catch {
            return Resolution(message: "Could not start document resolution: \(error.localizedDescription)")
        }
        return Resolution(message: "Save this document, then move its window to Tray again.")
    }
}
