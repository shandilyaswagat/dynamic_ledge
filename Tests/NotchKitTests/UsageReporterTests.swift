import Foundation
import Testing
@testable import NotchKit

@Suite("Anonymous usage")
@MainActor
struct UsageReporterTests {
    /// Records what the reporter sends, and answers as the server would.
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        var accepts = true

        var requests: [URLRequest] { lock.withLock { _requests } }

        func send(_ request: URLRequest) -> Bool {
            lock.withLock {
                _requests.append(request)
                return accepts
            }
        }

        func signals(_ index: Int) -> [[String: Any]] {
            guard let body = requests[index].httpBody,
                  let array = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return [] }
            return array
        }
    }

    private func make(appID: String = "APP-ID", version: String = "1.5.0", defaults: UserDefaults? = nil,
                      server: Server) -> (UsageReporter, UserDefaults) {
        let defaults = defaults ?? UserDefaults(suiteName: "usage-\(UUID().uuidString)")!
        let reporter = UsageReporter(defaults: defaults, appID: appID,
                                     info: ["CFBundleShortVersionString": version]) { server.send($0) }
        return (reporter, defaults)
    }

    @Test func sendsOncePerDay() async {
        let server = Server()
        let (reporter, defaults) = make(server: server)
        defaults.set("1.5.0", forKey: UsageReporter.Key.lastVersion)
        reporter.start(isNewInstall: false)
        reporter.stop()
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await reporter.sendIfDue(now: morning))
        #expect(await !reporter.sendIfDue(now: morning.addingTimeInterval(3600)), "already sent today")
        #expect(await reporter.sendIfDue(now: morning.addingTimeInterval(86_400)))
        #expect(server.requests.count == 2)
        #expect(server.signals(0).map { $0["type"] as? String } == ["App.active"])
    }

    @Test func newInstallIsCountedOnce() async {
        let server = Server()
        let (reporter, _) = make(server: server)
        reporter.start(isNewInstall: true)
        reporter.stop()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        await reporter.sendIfDue(now: now)
        await reporter.sendIfDue(now: now.addingTimeInterval(86_400))
        #expect(server.signals(0).map { $0["type"] as? String } == ["App.installed", "App.active"])
        #expect(server.signals(1).map { $0["type"] as? String } == ["App.active"])
    }

    @Test func updateIsCountedOnceWithTheOldVersion() async {
        let server = Server()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (installed, defaults) = make(version: "1.5.0", server: server)
        installed.start(isNewInstall: true)
        installed.stop()
        await installed.sendIfDue(now: now)
        #expect(!server.signals(0).contains { $0["type"] as? String == "App.updated" }, "a new install isn't an update")

        // Updated later the same day: sent straight away, without counting the day twice.
        let (updated, _) = make(version: "1.5.1", defaults: defaults, server: server)
        updated.start(isNewInstall: false)
        updated.stop()
        #expect(await updated.sendIfDue(now: now.addingTimeInterval(3600)))
        #expect(server.signals(1).map { $0["type"] as? String } == ["App.updated"])
        let payload = server.signals(1).first?["payload"] as? [String: String]
        #expect(payload?["previousVersion"] == "1.5.0")
        #expect(payload?["TelemetryDeck.AppInfo.version"] == "1.5.1")
        #expect(await !updated.sendIfDue(now: now.addingTimeInterval(7200)))
        await updated.sendIfDue(now: now.addingTimeInterval(86_400))
        #expect(server.signals(2).map { $0["type"] as? String } == ["App.active"])
    }

    @Test func macsCountedBeforeVersionsWereKeptCountAsUpdated() async {
        let server = Server()
        let defaults = UserDefaults(suiteName: "usage-\(UUID().uuidString)")!
        // What 1.4.3 leaves behind: an ID and the last day, but no version.
        defaults.set(UUID().uuidString, forKey: UsageReporter.Key.userID)
        defaults.set("2000-01-01", forKey: UsageReporter.Key.lastDay)
        let (reporter, _) = make(defaults: defaults, server: server)
        reporter.start(isNewInstall: false)
        reporter.stop()
        await reporter.sendIfDue(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(server.signals(0).map { $0["type"] as? String } == ["App.active", "App.updated"])
        let updated = server.signals(0).last?["payload"] as? [String: String]
        #expect(updated?["previousVersion"] == "unknown")
        let active = server.signals(0).first?["payload"] as? [String: String]
        #expect(active?["previousVersion"] == nil, "only the update says where it came from")
    }

    @Test func aCrashIsSentOnceOnTheNextLaunch() async {
        let server = Server()
        let defaults = UserDefaults(suiteName: "usage-\(UUID().uuidString)")!
        defaults.set("1.5.0", forKey: UsageReporter.Key.lastVersion)
        let (first, _) = make(defaults: defaults, server: server)
        first.start(isNewInstall: false)
        // No stop(): the app ended without quitting.
        let (second, _) = make(defaults: defaults, server: server)
        second.start(isNewInstall: false)
        second.stop()
        await second.sendIfDue(now: Date(timeIntervalSince1970: 1_800_000_000))
        let types = server.signals(0).map { $0["type"] as? String }
        #expect(types == ["App.active", "App.crashed"])
        let payload = server.signals(0).last?["payload"] as? [String: String]
        #expect(payload?["crashedVersion"] == "1.5.0")

        // Quitting properly isn't a crash.
        let (third, _) = make(defaults: defaults, server: server)
        third.start(isNewInstall: false)
        third.stop()
        #expect(await !third.sendIfDue(now: Date(timeIntervalSince1970: 1_800_000_100)), "nothing new to send")
    }

    @Test func updatesSayHowTheyStartedAndFailuresWhere() async {
        let server = Server()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (old, defaults) = make(version: "1.5.0", server: server)
        defaults.set("1.5.0", forKey: UsageReporter.Key.lastVersion)
        old.start(isNewInstall: false)
        old.stop()
        await old.sendIfDue(now: now)

        old.noteUpdateStarting(automatically: false)
        old.noteUpdateFailed(step: "download", error: "URLError")
        await old.sendIfDue(now: now.addingTimeInterval(60))
        #expect(server.signals(1).map { $0["type"] as? String } == ["App.updateFailed"])
        let failure = server.signals(1).first?["payload"] as? [String: String]
        #expect(failure?["failedStep"] == "download")
        #expect(failure?["errorKind"] == "URLError")
        #expect(failure?["updateTrigger"] == "clicked")

        old.noteUpdateStarting(automatically: true)
        let (updated, _) = make(version: "1.5.1", defaults: defaults, server: server)
        updated.start(isNewInstall: false)
        updated.stop()
        await updated.sendIfDue(now: now.addingTimeInterval(120))
        let update = server.signals(2).first?["payload"] as? [String: String]
        #expect(server.signals(2).map { $0["type"] as? String } == ["App.updated"])
        #expect(update?["updateTrigger"] == "automatic")
        #expect(update?["previousVersion"] == "1.5.0")
    }

    @Test func onlyTheLastFewEventsWait() {
        let (reporter, defaults) = make(server: Server())
        for _ in 0..<25 { reporter.record("App.crashed") }
        #expect((defaults.array(forKey: UsageReporter.Key.queued) ?? []).count == UsageReporter.maximumQueued)
    }

    @Test func failedSendIsRetried() async {
        let server = Server()
        server.accepts = false
        let (reporter, defaults) = make(server: server)
        reporter.start(isNewInstall: true)
        reporter.stop()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await !reporter.sendIfDue(now: now))
        #expect(defaults.string(forKey: UsageReporter.Key.lastDay) == nil)
        server.accepts = true
        #expect(await reporter.sendIfDue(now: now.addingTimeInterval(3600)))
        #expect(server.signals(1).map { $0["type"] as? String } == ["App.installed", "App.active"],
                "the install isn't lost when the first try fails")
    }

    @Test func sendsNothingWithoutAnAppID() async {
        let server = Server()
        let (reporter, defaults) = make(appID: "", server: server)
        reporter.start(isNewInstall: true)
        #expect(await !reporter.sendIfDue(now: Date()))
        #expect(server.requests.isEmpty)
        #expect(defaults.string(forKey: UsageReporter.Key.userID) == nil, "no ID is made either")
    }

    @Test func sendsOnlyAHashedIDAndVersions() async throws {
        let server = Server()
        let (reporter, defaults) = make(server: server)
        reporter.start(isNewInstall: false)
        reporter.stop()
        await reporter.sendIfDue(now: Date())
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == UsageReporter.endpoint)
        let signal = try #require(server.signals(0).first)
        let id = try #require(defaults.string(forKey: UsageReporter.Key.userID))
        #expect(signal["appID"] as? String == "APP-ID")
        #expect(signal["clientUser"] as? String == UsageReporter.hashed(id))
        #expect(signal["clientUser"] as? String != id)
        #expect((signal["clientUser"] as? String)?.count == 64)
        let payload = try #require(signal["payload"] as? [String: String])
        #expect(payload["TelemetryDeck.Device.platform"] == "macOS")
        #expect(payload["TelemetryDeck.Device.modelName"]?.hasPrefix("Mac") == true, "the kind of Mac, like Mac14,2")
        #expect(signal["isTestMode"] as? Bool == true, "test builds don't count")
    }

    @Test func daysAreUTC() {
        // 23:30 in UTC on one day is already the next day in India.
        let late = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400) + 84_600)
        #expect(UsageReporter.day(of: late) == UsageReporter.day(of: late.addingTimeInterval(-3600)))
        #expect(UsageReporter.day(of: late) != UsageReporter.day(of: late.addingTimeInterval(3600)))
    }

    @Test func sharingIsOnByDefaultAndRemembered() {
        let defaults = UserDefaults(suiteName: "usage-settings-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.sharesUsage)
        settings.sharesUsage = false
        #expect(!SettingsStore(defaults: defaults).sharesUsage)
    }
}
