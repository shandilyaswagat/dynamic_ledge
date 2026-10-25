import CryptoKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Signed updates")
struct UpdateVerificationTests {
    private let identifier = "com.rectircle.DynamicNotch"

    private func fixture(key: Curve25519.Signing.PrivateKey, image: Data = Data("release".utf8),
                         version: String = "1.3.0", bundle: String = "com.rectircle.DynamicNotch",
                         size: Int? = nil, fileName: String = "DynamicNotch.dmg") throws -> Data {
        let payload = try JSONEncoder().encode(UpdateManifest(version: version, bundleIdentifier: bundle,
            fileName: fileName, size: size ?? image.count,
            sha256: SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()))
        return try JSONEncoder().encode(SignedUpdateManifest(payload: payload, signature: key.signature(for: payload)))
    }

    @Test func acceptsAuthenticRelease() throws {
        let key = Curve25519.Signing.PrivateKey()
        let image = Data("release".utf8)
        let manifest = try UpdateVerification.manifest(fixture(key: key),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            version: #require(SemanticVersion("1.3.0")), bundleIdentifier: identifier)
        try UpdateVerification.verify(image, manifest: manifest)
        #expect(throws: (any Error).self) {
            try UpdateVerification.verify(Data("tampered".utf8), manifest: manifest)
        }
        #expect(throws: (any Error).self) {
            try UpdateVerification.verify(Data("Release".utf8), manifest: manifest)
        }
    }

    @Test func rejectsWrongKeysAndMissingSignatures() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = try fixture(key: key)
        let version = try #require(SemanticVersion("1.3.0"))
        for publicKey in ["", "invalid", Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()] {
            #expect(throws: (any Error).self) {
                try UpdateVerification.manifest(data, publicKey: publicKey, version: version, bundleIdentifier: identifier)
            }
        }
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        for invalid in [Data("{}".utf8), Data("checksum".utf8),
                        try JSONEncoder().encode(SignedUpdateManifest(payload: Data("changed".utf8), signature: Data(repeating: 0, count: 64)))] {
            #expect(throws: (any Error).self) {
                try UpdateVerification.manifest(invalid, publicKey: publicKey, version: version, bundleIdentifier: identifier)
            }
        }
    }

    @Test func rejectsReplayAndWrongProduct() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let version = try #require(SemanticVersion("1.3.0"))
        for data in [try fixture(key: key, version: "1.2.0"),
                     try fixture(key: key, bundle: "com.attacker.app"),
                     try fixture(key: key, size: 0),
                     try fixture(key: key, fileName: "Other.dmg")] {
            #expect(throws: (any Error).self) {
                try UpdateVerification.manifest(data, publicKey: publicKey, version: version, bundleIdentifier: identifier)
            }
        }
    }

    @Test func rejectsPayloadChangedAfterSigning() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try JSONDecoder().decode(SignedUpdateManifest.self, from: fixture(key: key))
        var altered = envelope.payload
        altered.append(0x20)
        let data = try JSONEncoder().encode(SignedUpdateManifest(payload: altered, signature: envelope.signature))
        #expect(throws: (any Error).self) {
            try UpdateVerification.manifest(data, publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                version: #require(SemanticVersion("1.3.0")), bundleIdentifier: identifier)
        }
    }
}

@Suite("Update key")
struct UpdateKeyTests {
    @Test func onlyARealKeyAllowsInstalling() {
        #expect(!Updater.isUsableKey(nil))
        #expect(!Updater.isUsableKey(""))
        #expect(!Updater.isUsableKey("__UPDATE_PUBLIC_KEY__"))
        #expect(Updater.isUsableKey(Data(repeating: 7, count: 32).base64EncodedString()))
    }

    @Test func installsInPlaceOnlyWithAKeyAndASignedRelease() throws {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        let app = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Dynamic Notch.app")
        let page = try #require(URL(string: "https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v9.0.0"))
        let image = try #require(URL(string: "https://github.com/shandilyaswagat/dynamic_notch/releases/download/v9.0.0/DynamicNotch.dmg"))
        var release = ReleaseInfo(version: try #require(SemanticVersion("9.0.0")), diskImage: image, checksum: nil,
                                  signedManifest: image.deletingLastPathComponent().appendingPathComponent("DynamicNotch.update.json"),
                                  page: page)
        #expect(Updater.canInstallInPlace(release, app: app, key: key))
        #expect(!Updater.canInstallInPlace(release, app: app, key: ""), "a build without a key can only download")
        release.signedManifest = nil
        #expect(!Updater.canInstallInPlace(release, app: app, key: key), "an unsigned release can only download")
    }
}
