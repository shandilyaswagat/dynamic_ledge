import AppKit
import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("File conversion and original preservation")
struct FileConverterTests {
    private func createTestImage(at url: URL) throws -> Data {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("Could not create test PNG image")
        }
        try png.write(to: url)
        return png
    }

    @Test func formatDetectionIdentifiesImageTypes() {
        #expect(FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/photo.png")))
        #expect(FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/photo.JPG")))
        #expect(FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/photo.webp")))
        #expect(FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/photo.heic")))
        #expect(!FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/song.mp3")))
        #expect(!FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/doc.pdf")))

        let available = FileConverter.availableExportFormats(for: URL(fileURLWithPath: "/tmp/photo.png"))
        #expect(!available.contains(.png))
        #expect(available.contains(.jpeg))
        #expect(available.contains(.tiff))
    }

    @Test func convertImagePreservesOriginalFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalURL = tempDir.appendingPathComponent("sample.png")
        let originalBytes = try createTestImage(at: originalURL)

        let destDir = tempDir.appendingPathComponent("converted")
        let resultURL = try FileConverter.convertImage(at: originalURL, to: .jpeg, destinationFolder: destDir)

        #expect(FileManager.default.fileExists(atPath: resultURL.path))
        #expect(resultURL.pathExtension.lowercased() == "jpg")
        #expect(resultURL != originalURL)

        // Strict preservation: original must still exist and have unchanged content
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        let afterBytes = try Data(contentsOf: originalURL)
        #expect(afterBytes == originalBytes)
    }

    @Test func onlyOffersFormatsThisMacCanSave() {
        let png = URL(fileURLWithPath: "/tmp/photo.png")
        #expect(!FileConverter.availableExportFormats(for: png, writable: [.png, .jpeg]).contains(.webp))
        #expect(FileConverter.availableExportFormats(for: png, writable: [.png, .jpeg]) == [.jpeg])
        #expect(FileConverter.availableExportFormats(for: URL(fileURLWithPath: "/tmp/scan.tif"), writable: [.tiff, .png]) == [.png])
    }

    @Test func trayConvertSavesACopyBesideTheOriginalAndAddsIt() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let originalURL = tempDir.appendingPathComponent("sample.png")
        let originalBytes = try createTestImage(at: originalURL)

        let tray = TrayStore(folder: tempDir, defaults: nil)
        tray.add([originalURL])
        let item = try #require(tray.items.first)
        tray.convert(item, to: .jpeg)
        let deadline = Date().addingTimeInterval(5)
        while tray.items.count < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }

        let copy = try #require(tray.items.first { $0.url.pathExtension == "jpg" })
        #expect(copy.url.deletingLastPathComponent().standardizedFileURL == tempDir.standardizedFileURL)
        #expect(try Data(contentsOf: originalURL) == originalBytes)
    }
}
