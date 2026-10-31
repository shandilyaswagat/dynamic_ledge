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

    @Test func trayStoreConvertAddsNewConvertedItem() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalURL = tempDir.appendingPathComponent("input.png")
        _ = try createTestImage(at: originalURL)

        let store = TrayStore(folder: tempDir)
        store.add([originalURL])
        #expect(store.items.count == 1)

        let item = store.items[0]
        let converted = store.convert(item: item, to: .tiff)
        #expect(converted != nil)
        #expect(store.items.count == 2)
        #expect(store.items.contains { $0.url.pathExtension == "tiff" })
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
    }
}
