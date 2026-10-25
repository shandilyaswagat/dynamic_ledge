import AppKit
import CryptoKit
import Observation
import Security
import os

/// Keeps the app up to date from its GitHub releases. Once a day (when allowed in Settings) it asks
/// GitHub for the latest release; checks use HTTPS. Installing
/// downloads the disk image, verifies its signed manifest with an embedded public key, swaps the app in
/// place and reopens it.
@MainActor
@Observable
public final class Updater {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// Called once per new version found by an automatic check.
    @ObservationIgnored public var onAvailable: ((ReleaseInfo) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "updates")

    public static let latestRelease = URL(string: "https://api.github.com/repos/shandilyaswagat/dynamic_notch/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 3600
    /// The app bundle is small. A firm cap prevents untrusted release metadata from making the
    /// updater consume arbitrary memory or storage before signature verification.
    nonisolated static let maximumDiskImageBytes = 100 * 1024 * 1024
    nonisolated static let maximumManifestBytes = 16 * 1024

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var currentVersion: SemanticVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init)
    }

    public var availableRelease: ReleaseInfo? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks now if a day has passed, then looks again every few hours.
    public func startAutomaticChecks() {
        guard timer == nil else { return }
        checkIfDue()
        let timer = Timer(timeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    private func checkIfDue() {
        let last = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        check(userInitiated: false)
    }

    public func check(userInitiated: Bool = true) {
        if case .installing = state { return }
        state = .checking
        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: Self.latestRelease, timeoutInterval: 20)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let release = ReleaseInfo.parse(data) else {
                    throw UpdateError.unreadable
                }
                self.defaults.set(Date(), forKey: Key.lastCheck)
                if let current = self.currentVersion, release.version > current {
                    self.state = .available(release)
                    let announced = self.defaults.string(forKey: Key.announced)
                    if !userInitiated, announced != release.version.description {
                        self.defaults.set(release.version.description, forKey: Key.announced)
                        self.onAvailable?(release)
                    }
                } else {
                    self.state = .upToDate
                }
            } catch {
                self.log.notice("Update check failed: \(error.localizedDescription, privacy: .public)")
                self.state = userInitiated ? .failed(String(localized: "Couldn't reach GitHub. Try again later.")) : .idle
            }
        }
    }

    /// Downloads, verifies and installs the release, then relaunches. Opens the release page
    /// instead when the app can't replace itself (read-only location, or run from a disk image).
    public func install(_ release: ReleaseInfo) {
        let destination = Bundle.main.bundleURL
        guard canInstallInPlace(release) else {
            NSWorkspace.shared.open(release.page)
            return
        }
        state = .installing
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "DNUpdatePublicKey") as? String,
                      let identifier = Bundle.main.bundleIdentifier,
                      let current = self.currentVersion, release.version > current else {
                    throw UpdateError.unreadable
                }
                let staged = try await Self.download(release, publicKey: publicKey, bundleIdentifier: identifier)
                try Self.relaunch(replacing: destination, with: staged)
            } catch {
                self.log.error("Update failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(String(localized: "The update couldn't be installed. You can download it from GitHub instead."))
            }
        }
    }

    // MARK: Steps

    enum UpdateError: Error {
        case unreadable
        case noApp
    }

    /// Whether Install can swap the app in place. When it can't, the button says Download and
    /// opens the release page, so it never promises a relaunch that won't happen.
    public func canInstallInPlace(_ release: ReleaseInfo) -> Bool {
        Self.canInstallInPlace(release, app: Bundle.main.bundleURL,
                               key: Bundle.main.object(forInfoDictionaryKey: "DNUpdatePublicKey") as? String)
    }

    /// No release-signing key in this build, or no signed manifest on the release, means the
    /// update can't be verified, so it has to be downloaded by hand.
    nonisolated static func canInstallInPlace(_ release: ReleaseInfo, app: URL, key: String?) -> Bool {
        canReplace(app) && isUsableKey(key) && release.signedManifest != nil
    }

    /// A base64 Ed25519 public key (32 bytes), not an empty or unfilled placeholder.
    nonisolated static func isUsableKey(_ key: String?) -> Bool {
        guard let key, let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    nonisolated static func canReplace(_ app: URL) -> Bool {
        let path = app.path
        // Translocated or mounted copies can't be swapped in place.
        guard !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Downloads and verifies the disk image, then copies the app out of it into a staging folder.
    nonisolated static func download(_ release: ReleaseInfo, publicKey: String, bundleIdentifier: String) async throws -> URL {
        guard let manifestURL = release.signedManifest,
              manifestURL.scheme == "https", release.diskImage.scheme == "https" else {
            throw UpdateError.unreadable
        }
        let (manifestData, manifestResponse) = try await boundedData(from: manifestURL, maximumBytes: maximumManifestBytes)
        guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200,
              manifestResponse.url.map({ ReleaseInfo.isAllowedGitHubURL($0, forAsset: true) }) == true else {
            throw UpdateError.unreadable
        }
        let manifest = try UpdateVerification.manifest(manifestData, publicKey: publicKey,
                                                      version: release.version, bundleIdentifier: bundleIdentifier)
        guard manifest.size <= maximumDiskImageBytes else { throw UpdateError.unreadable }
        let (image, response) = try await boundedData(from: release.diskImage, maximumBytes: manifest.size)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else {
            throw UpdateError.unreadable
        }
        guard response.url.map({ ReleaseInfo.isAllowedGitHubURL($0, forAsset: true) }) == true else {
            throw UpdateError.unreadable
        }
        try UpdateVerification.verify(image, manifest: manifest)

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("DynamicNotchUpdate-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mount")
        let staged = work.appendingPathComponent("staged")
        var keepStaged = false
        defer { if !keepStaged { try? FileManager.default.removeItem(at: work) } }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let diskImage = work.appendingPathComponent(ReleaseInfo.diskImageName)
        try image.write(to: diskImage, options: .atomic)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", diskImage.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noApp }
        let copy = staged.appendingPathComponent(app.lastPathComponent)
        try run("/usr/bin/ditto", [app.path, copy.path])
        try validateApp(copy, version: release.version, bundleIdentifier: bundleIdentifier)
        keepStaged = true
        return copy
    }

    /// Streams into bounded memory instead of asking URLSession to first save an untrusted
    /// response to disk. The caller verifies its signature and exact byte count afterward.
    nonisolated static func boundedData(from url: URL, maximumBytes: Int) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard response.expectedContentLength <= Int64(maximumBytes) || response.expectedContentLength < 0 else {
            throw UpdateError.unreadable
        }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw UpdateError.unreadable }
            data.append(byte)
        }
        return (data, response)
    }

    /// Developer ID installations require the same Apple-trusted signing team on updates.
    /// Ad-hoc installations rely on the independently pinned Ed25519 release key.
    nonisolated static func validateApp(_ app: URL, version: SemanticVersion, bundleIdentifier: String) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.description else {
            throw UpdateError.unreadable
        }
        var currentCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode else { throw UpdateError.unreadable }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(currentCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else {
            throw UpdateError.unreadable
        }
        let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        guard let team else { return }
        // Restrict interpolation to the characters used by Apple Team IDs and bundle IDs.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard team.unicodeScalars.allSatisfy(allowed.contains),
              bundleIdentifier.unicodeScalars.allSatisfy(allowed.contains) else { throw UpdateError.unreadable }
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(bundleIdentifier)\""
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess,
              let candidate, let requirement,
              SecStaticCodeCheckValidity(candidate, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw UpdateError.unreadable
        }
    }

    /// Hands over to a small script that waits for this app to quit, swaps the bundle and reopens it.
    static func relaunch(replacing destination: URL, with staged: URL) throws {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old" && mv "$2" "$2.old" && /usr/bin/ditto "$3" "$2" && rm -rf "$2.old" || { rm -rf "$2"; mv "$2.old" "$2"; }
        /usr/bin/open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), destination.path, staged.path]
        try process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unreadable }
        return process.terminationStatus
    }

    private enum Key {
        static let lastCheck = "updates.lastCheck"
        static let announced = "updates.announced"
    }
}
