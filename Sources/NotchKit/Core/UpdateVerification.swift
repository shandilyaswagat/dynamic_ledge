import CryptoKit
import Foundation

/// The signature covers the exact payload bytes, avoiding JSON canonicalization assumptions.
struct SignedUpdateManifest: Codable {
    let payload: Data
    let signature: Data
}

struct UpdateManifest: Codable {
    let version: String
    let bundleIdentifier: String
    let fileName: String
    let size: Int
    let sha256: String
}

enum UpdateVerification {
    enum Failure: Error { case untrustedUpdate }

    static func manifest(_ data: Data, publicKey: String, version: SemanticVersion,
                         bundleIdentifier: String) throws -> UpdateManifest {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let envelope = try? JSONDecoder().decode(SignedUpdateManifest.self, from: data),
              key.isValidSignature(envelope.signature, for: envelope.payload),
              let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: envelope.payload),
              manifest.version == version.description,
              manifest.bundleIdentifier == bundleIdentifier,
              manifest.fileName == ReleaseInfo.diskImageName,
              manifest.size > 0,
              manifest.sha256.count == 64,
              manifest.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw Failure.untrustedUpdate
        }
        return manifest
    }

    static func verify(_ image: Data, manifest: UpdateManifest) throws {
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        guard image.count == manifest.size, digest == manifest.sha256 else {
            throw Failure.untrustedUpdate
        }
    }
}
