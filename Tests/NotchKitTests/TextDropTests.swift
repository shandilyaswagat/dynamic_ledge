import AppKit
import Testing
@testable import NotchKit

@MainActor
@Suite("Text drop actions")
struct TextDropTests {
    private func model() -> IslandModel {
        let defaults = UserDefaults(suiteName: "TextDropTests-\(UUID().uuidString)")!
        return IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil, defaults: nil), notes: NotesStore(defaults: defaults))
    }

    @Test func rejectsFilesAndLinksButAcceptsSelection() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("  Selected words\n", forType: .string)
        #expect(TextDropReader.text(from: board) == "Selected words")
        board.clearContents()
        board.setString("https://example.invalid/file.pdf", forType: .string)
        #expect(TextDropReader.text(from: board) == nil)
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/file.txt") as NSURL])
        #expect(TextDropReader.text(from: board) == nil)
        #expect(TextDropReader.clean(" \0\n") == nil)
    }

    @Test func targetGeometryMatchesVisibleActions() {
        let rect = CGRect(x: 20, y: 40, width: 300, height: 100)
        #expect(TextDropAction.destination(at: CGPoint(x: 30, y: 50), content: rect, notes: true) == .translate)
        #expect(TextDropAction.destination(at: CGPoint(x: 170, y: 50), content: rect, notes: true) == .notes)
        #expect(TextDropAction.destination(at: CGPoint(x: 300, y: 50), content: rect, notes: true) == .copy)
        #expect(TextDropAction.destination(at: CGPoint(x: 170, y: 50), content: rect, notes: false) == .copy)
        #expect(TextDropAction.destination(at: .zero, content: rect, notes: true) == nil)
    }

    @Test func preservesFormattingAndSavesAppendedNote() throws {
        let model = model()
        model.settings.notesEnabled = true
        model.notes.update(NSAttributedString(string: "Existing", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
        #expect(model.acceptTextDrop("New text", action: .notes))
        #expect(model.notes.text == "Existing\nNew text")
        #expect((model.notes.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        model.settings.notesEnabled = false
        #expect(!model.acceptTextDrop("Hidden note", action: .notes))
        #expect(model.notes.text == "Existing\nNew text")
    }

    @Test func copyAndTranslationOnlyRunOnDrop() throws {
        let model = model()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(model.acceptTextDrop("Copied words", action: .copy, pasteboard: board))
        #expect(board.string(forType: .string) == "Copied words")
        var opened: URL?
        #expect(model.acceptTextDrop("Hello & नमस्ते", action: .translate, openURL: { opened = $0; return true }))
        let components = try #require(opened.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.host == "translate.google.com")
        #expect(components.queryItems?.first { $0.name == "text" }?.value == "Hello & नमस्ते")
        let long = try #require(TextDropReader.translationURL(String(repeating: "😀", count: 6000)))
        #expect(URLComponents(url: long, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value?.count == 5000)
    }

    @Test func worksWithFileDestinationsOffAndClearsOnExit() {
        let model = model()
        model.screen = .sample
        model.settings.trayEnabled = false
        model.settings.airDropEnabled = false
        model.isTextDrag = true
        model.fileDragChanged(isDragging: true, at: CGPoint(x: model.engine.dropZone.midX, y: 20))
        if case .drop = model.presentation {} else { Issue.record("Text drag must reveal actions") }
        model.fileDragChanged(isDragging: false, at: nil)
        #expect(!model.isTextDrag && model.targetedTextAction == nil && !model.isFileDragNear)
    }
}
