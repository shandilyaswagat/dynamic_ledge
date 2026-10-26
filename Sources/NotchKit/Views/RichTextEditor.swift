import AppKit
import Observation
import SwiftUI

/// Lets buttons outside the editor format what's selected (or what you type next).
@MainActor
@Observable
final class RichTextController {
    /// Colours for the note's text, in the order the colour button steps through them.
    static let palette: [NSColor] = [
        .white,
        NSColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1),
        NSColor(red: 1, green: 214 / 255, blue: 10 / 255, alpha: 1),
        NSColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1),
        NSColor(red: 1, green: 69 / 255, blue: 58 / 255, alpha: 1),
    ]

    @ObservationIgnored weak var textView: NSTextView?
    private(set) var colorIndex = 0
    var baseSize: CGFloat = 13

    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    func toggleUnderline() {
        apply { attributes in
            let on = (attributes[.underlineStyle] as? Int ?? 0) != 0
            attributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
        }
    }

    /// Steps between normal and large text.
    func toggleSize() {
        let large = (baseSize * 1.35).rounded()
        apply { attributes in
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: self.baseSize)
            let size = font.pointSize > self.baseSize + 0.5 ? self.baseSize : large
            attributes[.font] = NSFontManager.shared.convert(font, toSize: size)
        }
    }

    func nextColor() {
        colorIndex = (colorIndex + 1) % Self.palette.count
        let color = Self.palette[colorIndex]
        apply { $0[.foregroundColor] = color }
    }

    var currentColor: Color { Color(nsColor: Self.palette[colorIndex]) }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        apply { attributes in
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: self.baseSize)
            let has = NSFontManager.shared.traits(of: font).contains(trait)
            attributes[.font] = has
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
    }

    /// Changes the selection, or the typing style when nothing is selected.
    private func apply(_ change: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            change(&attributes)
            textView.typingAttributes = attributes
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { existing, subrange, _ in
            var attributes = existing
            change(&attributes)
            storage.setAttributes(attributes, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }
}

/// A plain-looking text area that keeps formatting, saving into the notes as you type.
struct RichTextEditor: NSViewRepresentable {
    let notes: NotesStore
    let controller: RichTextController
    var fontSize: CGFloat
    var focusOnAppear = false
    var onFocus: (Bool) -> Void = { _ in }
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let textView = FocusTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.typingAttributes = Self.baseAttributes(size: fontSize)
        textView.delegate = context.coordinator
        textView.onFocus = { focused in onFocus(focused) }
        textView.onEscape = { onEscape() }
        scroll.documentView = textView
        controller.textView = textView
        controller.baseSize = fontSize
        context.coordinator.load(into: textView)
        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        if context.coordinator.revision != notes.revision {
            context.coordinator.load(into: textView)
        }
    }

    static func baseAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.white]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var revision = -1

        init(_ parent: RichTextEditor) { self.parent = parent }

        func load(into textView: NSTextView) {
            revision = parent.notes.revision
            let note = NSMutableAttributedString(attributedString: parent.notes.attributedText)
            // Text without a colour or font of its own reads as white system text on black.
            let whole = NSRange(location: 0, length: note.length)
            note.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
                if value == nil { note.addAttribute(.foregroundColor, value: NSColor.white, range: range) }
            }
            note.enumerateAttribute(.font, in: whole) { value, range, _ in
                if value == nil { note.addAttribute(.font, value: NSFont.systemFont(ofSize: parent.fontSize), range: range) }
            }
            textView.textStorage?.setAttributedString(note)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.notes.update(textView.attributedString())
        }
    }
}

/// Tells SwiftUI when it gains or loses the keyboard, and turns Escape into "close".
private final class FocusTextView: NSTextView {
    var onFocus: (Bool) -> Void = { _ in }
    var onEscape: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus(false) }
        return accepted
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}
