import CryptoKit
import Foundation
import os

/// Counts how many Macs use the app: once a day it sends TelemetryDeck one anonymous signal with
/// the app and macOS versions and the Mac's model (like "Mac14,2"), and one more the first time a
/// new version runs. A failed update and a quit that wasn't clean (a crash) are each sent once
/// too, with only the version and what kind of failure it was. The Mac is a random ID made on first launch and hashed before it
/// leaves; nothing about you, your files or what you do in the app is sent.
@MainActor
public final class UsageReporter {
    /// The TelemetryDeck app this counts towards. Empty sends nothing.
    static let telemetryDeckAppID = "7AEA9D8F-9761-4EE6-BFB6-46D4EB1E8D5B"
    /// The organization's namespace endpoint, which TelemetryDeck recommends over the plain one.
    nonisolated static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/namespace/com.talvioh/")!

    /// Sends one request; true when it was accepted.
    typealias Sender = @Sendable (URLRequest) async -> Bool

    private let defaults: UserDefaults
    private let appID: String
    private let info: [String: Any]
    private let send: Sender
    private let sessionID = UUID().uuidString
    private var timer: Timer?
    private var isSending = false
    private let log = Logger(subsystem: Log.subsystem, category: "usage")

    public convenience init() {
        self.init(appID: Self.telemetryDeckAppID, send: Self.post)
    }

    init(defaults: UserDefaults = .standard, appID: String,
         info: [String: Any] = Bundle.main.infoDictionary ?? [:], send: @escaping Sender) {
        self.defaults = defaults
        self.appID = appID
        self.info = info
        self.send = send
    }

    /// Sends today's signal soon, then looks again every hour (a Mac that sleeps through midnight,
    /// or was offline, still counts that day once it's back).
    /// - Parameter isNewInstall: this is the app's very first launch on this Mac.
    public func start(isNewInstall: Bool) {
        guard timer == nil, !appID.isEmpty else { return }
        if defaults.string(forKey: Key.userID) == nil {
            defaults.set(UUID().uuidString, forKey: Key.userID)
            defaults.set(isNewInstall, forKey: Key.pendingInstall)
        }
        // Still marked running: the last run ended without quitting (a crash, or a force quit).
        if defaults.bool(forKey: Key.running) {
            record("App.crashed", ["crashedVersion": defaults.string(forKey: Key.runningVersion) ?? "unknown"])
        }
        defaults.set(true, forKey: Key.running)
        defaults.set(info["CFBundleShortVersionString"] as? String ?? "0", forKey: Key.runningVersion)
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendIfDue() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { [weak self] in
            // Not during launch, which is busy enough.
            try? await Task.sleep(for: .seconds(20))
            self?.sendIfDue()
        }
    }

    /// Called on quit (and when usage sharing is turned off), so the next launch knows it ended cleanly.
    public func stop() {
        timer?.invalidate()
        timer = nil
        defaults.set(false, forKey: Key.running)
    }

    /// Keeps a one-off signal for the next send, and sends it soon if counting has started. Only
    /// the last few are kept, so nothing piles up while offline.
    public func record(_ type: String, _ payload: [String: String] = [:]) {
        guard !appID.isEmpty else { return }
        var queued = defaults.array(forKey: Key.queued) as? [[String: String]] ?? []
        queued.append(payload.merging(["type": type]) { _, new in new })
        defaults.set(Array(queued.suffix(Self.maximumQueued)), forKey: Key.queued)
        sendIfDue()
    }

    /// The updater is about to install, by itself or because it was clicked; the next version's
    /// App.updated says which.
    public func noteUpdateStarting(automatically: Bool) {
        defaults.set(automatically ? "automatic" : "clicked", forKey: Key.updateTrigger)
    }

    /// The update didn't install: says at which step and what kind of error, and forgets how it
    /// started so a later update isn't credited to it.
    public func noteUpdateFailed(step: String, error: String) {
        let trigger = defaults.string(forKey: Key.updateTrigger) ?? "clicked"
        defaults.removeObject(forKey: Key.updateTrigger)
        record("App.updateFailed", ["failedStep": step, "errorKind": error, "updateTrigger": trigger])
    }

    static let maximumQueued = 10

    private func sendIfDue() {
        guard timer != nil else { return }
        Task { await sendIfDue(now: Date()) }
    }

    /// Sends today's signal unless it already went out, and an update signal the first time a new
    /// version runs. True when something was sent.
    @discardableResult
    func sendIfDue(now: Date) async -> Bool {
        let day = Self.day(of: now)
        guard !isSending, !appID.isEmpty, let userID = defaults.string(forKey: Key.userID) else { return false }
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let isNewInstall = defaults.bool(forKey: Key.pendingInstall)
        // A Mac counted before versions were remembered (up to 1.4.3) has updated since, from a
        // version we don't know.
        let previousVersion = defaults.string(forKey: Key.lastVersion) ?? (isNewInstall ? version : "unknown")
        var signals: [Signal] = []
        if defaults.string(forKey: Key.lastDay) != day {
            if isNewInstall { signals.append(Signal(type: "App.installed")) }
            signals.append(Signal(type: "App.active"))
        }
        if previousVersion != version {
            // Installed by our updater (automatically or clicked), or some other way (a new
            // download, Homebrew).
            let trigger = defaults.string(forKey: Key.updateTrigger) ?? "other"
            signals.append(Signal(type: "App.updated", payload: ["previousVersion": previousVersion, "updateTrigger": trigger]))
        }
        let queued = defaults.array(forKey: Key.queued) as? [[String: String]] ?? []
        for entry in queued {
            guard let type = entry["type"] else { continue }
            signals.append(Signal(type: type, payload: entry.filter { $0.key != "type" }))
        }
        guard !signals.isEmpty else { return false }
        isSending = true
        defer { isSending = false }
        guard let request = Self.request(signals: signals, appID: appID, userID: userID, sessionID: sessionID,
                                         info: info) else { return false }
        guard await send(request) else {
            log.notice("Usage signal not sent; trying again later")
            return false
        }
        defaults.set(day, forKey: Key.lastDay)
        defaults.set(version, forKey: Key.lastVersion)
        defaults.set(false, forKey: Key.pendingInstall)
        defaults.removeObject(forKey: Key.updateTrigger)
        // Anything recorded while this was sending waits for the next one.
        let remaining = defaults.array(forKey: Key.queued) as? [[String: String]] ?? []
        defaults.set(Array(remaining.dropFirst(min(queued.count, remaining.count))), forKey: Key.queued)
        return true
    }

    // MARK: Request

    struct Signal: Equatable {
        var type: String
        /// Added to the shared payload, like App.updated's previous version.
        var payload: [String: String] = [:]
    }

    /// One POST with a signal per type. Same payload keys as TelemetryDeck's own Swift SDK, so its
    /// standard version and OS charts work.
    nonisolated static func request(signals: [Signal], appID: String, userID: String, sessionID: String,
                                    info: [String: Any]) -> URLRequest? {
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let payload: [String: String] = [
            "appVersion": version,
            "buildNumber": build,
            "platform": "macOS",
            "systemVersion": system,
            "isDebug": "\(isDebug)",
            "TelemetryDeck.AppInfo.version": version,
            "TelemetryDeck.AppInfo.buildNumber": build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(version) (build \(build))",
            "TelemetryDeck.Device.platform": "macOS",
            "TelemetryDeck.Device.operatingSystem": "macOS",
            "TelemetryDeck.Device.systemVersion": system,
            "TelemetryDeck.Device.systemMajorVersion": "\(os.majorVersion)",
            "TelemetryDeck.Device.systemMajorMinorVersion": "\(os.majorVersion).\(os.minorVersion)",
            "TelemetryDeck.Device.architecture": architecture,
            "TelemetryDeck.Device.modelName": modelName,
            "TelemetryDeck.RunContext.isDebug": "\(isDebug)",
        ]
        let signals: [[String: Any]] = signals.map { signal in
            let payload = payload.merging(signal.payload) { shared, _ in shared }
            let type = signal.type
            return [
                "appID": appID,
                "clientUser": hashed(userID),
                "sessionID": sessionID,
                "type": type,
                // Test builds show up only in TelemetryDeck's test mode.
                "isTestMode": isDebug,
                "payload": payload,
            ]
        }
        guard let body = try? JSONSerialization.data(withJSONObject: signals, options: .sortedKeys) else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// SHA-256, as the SDK does; TelemetryDeck salts and hashes it again before storing it.
    nonisolated static func hashed(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The calendar day in UTC, the day TelemetryDeck counts a signal in.
    nonisolated static func day(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The model identifier, like "Mac14,2" (a MacBook Air): a kind of Mac, not this one.
    nonisolated static var modelName: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private nonisolated static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private nonisolated static func post(_ request: URLRequest) async -> Bool {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
    }

    enum Key {
        static let userID = "usage.userID"
        static let lastDay = "usage.lastDay"
        static let pendingInstall = "usage.pendingInstall"
        static let lastVersion = "usage.lastVersion"
        static let queued = "usage.queued"
        static let running = "usage.running"
        static let runningVersion = "usage.runningVersion"
        static let updateTrigger = "usage.updateTrigger"
    }
}
