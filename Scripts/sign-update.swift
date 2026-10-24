#!/usr/bin/env swift
import CryptoKit
import Foundation

// Private keys are base64-encoded raw Ed25519 keys. Never commit or upload them.
struct Manifest: Codable {
    let version: String
    let bundleIdentifier: String
    let fileName: String
    let size: Int
    let sha256: String
}
struct Envelope: Codable { let payload: Data; let signature: Data }
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let args = CommandLine.arguments
if args.count == 3 && args[1] == "generate" {
    let path = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: path.path) else { fail("Key file already exists") }
    let key = Curve25519.Signing.PrivateKey()
    let data = Data(key.rawRepresentation.base64EncodedString().utf8)
    guard FileManager.default.createFile(atPath: path.path, contents: data,
                                        attributes: [.posixPermissions: 0o600]) else { fail("Could not create key") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if args.count == 7 && args[1] == "sign" {
    let raw = try String(contentsOfFile: args[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let bytes = Data(base64Encoded: raw) else { fail("Invalid private key") }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
    let plist = try Data(contentsOf: URL(fileURLWithPath: args[6]))
    guard let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
          info["DNUpdatePublicKey"] as? String == key.publicKey.rawRepresentation.base64EncodedString(),
          info["CFBundleIdentifier"] as? String == args[5],
          info["CFBundleShortVersionString"] as? String == args[4] else {
        fail("Signing key, version or bundle identifier does not match the built app")
    }
    let image = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    let manifest = Manifest(version: args[4], bundleIdentifier: args[5], fileName: "DynamicNotch.dmg",
                            size: image.count, sha256: SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined())
    let payload = try JSONEncoder().encode(manifest)
    let envelope = Envelope(payload: payload, signature: try key.signature(for: payload))
    try JSONEncoder().encode(envelope).write(to: URL(fileURLWithPath: args[3]).deletingLastPathComponent()
        .appendingPathComponent("DynamicNotch.update.json"), options: .atomic)
} else {
    fail("Usage: swift Scripts/sign-update.swift generate PRIVATE_KEY_PATH\n       swift Scripts/sign-update.swift sign PRIVATE_KEY_PATH DMG VERSION BUNDLE_ID BUILT_INFO_PLIST")
}
