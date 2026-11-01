import AppKit
import PDFKit
import Testing
@testable import NotchKit

@Suite("Tray zip and merge")
struct TrayActionsTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tray-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func image(at url: URL) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func pdf(at url: URL, pages: Int) throws {
        let document = PDFDocument()
        let page = NSImage(size: NSSize(width: 10, height: 10))
        for index in 0..<pages {
            page.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill(); page.unlockFocus()
            document.insert(try #require(PDFPage(image: page)), at: index)
        }
        #expect(document.write(to: url))
    }

    @Test func zipsOneFileUnderItsOwnName() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appendingPathComponent("Report.txt")
        try Data("hello".utf8).write(to: note)
        let zip = try TrayActions.zip([note])
        #expect(zip.lastPathComponent == "Report.zip")
        #expect(FileManager.default.fileExists(atPath: note.path), "the original stays")
    }

    @Test func zipsSeveralIntoArchiveWithoutOverwriting() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        #expect(try TrayActions.zip([a, b]).lastPathComponent == "Archive.zip")
        #expect(try TrayActions.zip([a, b]).lastPathComponent == "Archive 2.zip")
    }

    @Test func mergesPDFPagesAndImagesInOrder() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("two.pdf"), photo = dir.appendingPathComponent("photo.png")
        try pdf(at: doc, pages: 2)
        try image(at: photo)
        let merged = try TrayActions.mergePDF([doc, photo, dir.appendingPathComponent("notes.txt")])
        #expect(merged.lastPathComponent == "Merged.pdf")
        #expect(PDFDocument(url: merged)?.pageCount == 3)
        #expect(throws: TrayActions.Failure.nothingToUse) { try TrayActions.mergePDF([dir.appendingPathComponent("notes.txt")]) }
    }
}
