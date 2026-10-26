import AppKit
import Observation

/// One scratchpad, saved as you type and kept across launches. Formatting (bold, italic,
/// underline, colour, size) is kept as RTF next to the plain text.
@MainActor
@Observable
public final class NotesStore {
    /// The note without formatting, for previews and for older versions of the app.
    public private(set) var text: String
    /// The formatted note as saved. Nil when it has never been formatted.
    @ObservationIgnored private var rtf: Data?
    /// The latest formatted note from an editor, turned into RTF only when it's saved, so typing
    /// never pays for the conversion.
    @ObservationIgnored private var pending: NSAttributedString?
    /// Bumped whenever the note changes from outside an editor (cleared), so open editors reload.
    public private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let key = "notes.text"
    private static let rtfKey = "notes.rtf"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: Self.key) ?? ""
        rtf = defaults.data(forKey: Self.rtfKey)
        // A version without formatting may have changed the text since; trust the text then.
        if let rtf, Self.attributed(from: rtf)?.string != text {
            self.rtf = nil
        }
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The note with its formatting, for an editor to show.
    public var attributedText: NSAttributedString {
        pending ?? rtf.flatMap(Self.attributed(from:)) ?? NSAttributedString(string: text)
    }

    /// Called by an editor as you type (and when formatting changes).
    public func update(_ attributed: NSAttributedString) {
        pending = attributed.copy() as? NSAttributedString
        if attributed.string != text { text = attributed.string }
        scheduleSave()
    }

    /// Plain text, replacing any formatting.
    public func setText(_ value: String) {
        guard value != text else { return }
        text = value
        rtf = nil
        pending = nil
        revision += 1
        scheduleSave()
    }

    /// Writes now instead of waiting for typing to pause (on quit, or when the notch closes).
    public func save() {
        saveTask?.cancel()
        saveTask = nil
        if let pending {
            rtf = Self.rtfData(pending)
            self.pending = nil
        }
        defaults.set(text, forKey: Self.key)
        if let rtf {
            defaults.set(rtf, forKey: Self.rtfKey)
        } else {
            defaults.removeObject(forKey: Self.rtfKey)
        }
    }

    public func clear() {
        setText("")
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private static func rtfData(_ attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        return try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private static func attributed(from data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }
}
