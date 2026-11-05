import AppKit
import Testing
@testable import NotchKit

@MainActor
@Suite("Text from copied images")
struct ClipboardImageTextTests {
    private func picture(of text: String) -> Data {
        let image = NSImage(size: NSSize(width: 520, height: 120), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [
                .font: NSFont.systemFont(ofSize: 40, weight: .medium),
                .foregroundColor: NSColor.black,
            ])
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func copy(_ data: Data, types: [NSPasteboard.PasteboardType] = [.png], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes(types, owner: nil)
        for type in types { pasteboard.setData(data, forType: type) }
    }

    @Test func readsTextFromACopiedImageWhenTurnedOn() async {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        monitor.readsTextInImages = true
        monitor.start()
        defer { monitor.stop() }
        copy(picture(of: "Dynamic Ledge 42"), to: pasteboard)
        monitor.check()
        await monitor.recognition?.value
        #expect(monitor.history.entries.first?.text.contains("Dynamic Ledge") == true)
    }

    @Test func leavesImagesAloneByDefault() async {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        monitor.start()
        defer { monitor.stop() }
        copy(picture(of: "Dynamic Ledge 42"), to: pasteboard)
        monitor.check()
        #expect(monitor.recognition == nil)
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func onlyPicturesCount() {
        #expect(ClipboardRules.isImage(types: ["public.png"]))
        #expect(ClipboardRules.isImage(types: ["public.tiff"]))
        #expect(!ClipboardRules.isImage(types: ["public.file-url", "public.tiff"]), "a file copied in Finder")
        #expect(!ClipboardRules.isImage(types: ["public.utf8-plain-text"]))
    }
}
