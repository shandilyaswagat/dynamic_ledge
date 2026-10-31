import CryptoKit
import Foundation
import os

/// Counts how many Macs use the app: once a day it sends TelemetryDeck one anonymous signal with
/// the app and macOS versions. The Mac is a random ID made on first launch and hashed before it
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
    private let send: Sender
    private let sessionID = UUID().uuidString
    private var timer: Timer?
    private var isSending = false
    private let log = Logger(subsystem: Log.subsystem, category: "usage")

    public convenience init() {
        self.init(appID: Self.telemetryDeckAppID, send: Self.post)
    }

    init(defaults: UserDefaults = .standard, appID: String, send: @escaping Sender) {
        self.defaults = defaults
        self.appID = appID
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

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sendIfDue() {
        guard timer != nil else { return }
        Task { await sendIfDue(now: Date()) }
    }

    /// Sends today's signal unless it already went out. True when something was sent.
    @discardableResult
    func sendIfDue(now: Date) async -> Bool {
        let day = Self.day(of: now)
        guard !isSending, !appID.isEmpty, defaults.string(forKey: Key.lastDay) != day,
              let userID = defaults.string(forKey: Key.userID) else { return false }
        isSending = true
        defer { isSending = false }
        var types = ["App.active"]
        if defaults.bool(forKey: Key.pendingInstall) { types.insert("App.installed", at: 0) }
        guard let request = Self.request(types: types, appID: appID, userID: userID, sessionID: sessionID,
                                         info: Bundle.main.infoDictionary ?? [:]) else { return false }
        guard await send(request) else {
            log.notice("Usage signal not sent; trying again later")
            return false
        }
        defaults.set(day, forKey: Key.lastDay)
        defaults.set(false, forKey: Key.pendingInstall)
        return true
    }

    // MARK: Request

    /// One POST with a signal per type. Same payload keys as TelemetryDeck's own Swift SDK, so its
    /// standard version and OS charts work.
    nonisolated static func request(types: [String], appID: String, userID: String, sessionID: String,
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
            "TelemetryDeck.RunContext.isDebug": "\(isDebug)",
        ]
        let signals: [[String: Any]] = types.map {
            [
                "appID": appID,
                "clientUser": hashed(userID),
                "sessionID": sessionID,
                "type": $0,
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
    }
}
