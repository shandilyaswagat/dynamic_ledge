import AppKit

enum TextDropAction: String, CaseIterable, Sendable {
    case translate, notes, copy

    var title: String {
        switch self { case .translate: "Translate"; case .notes: "Save in Notes"; case .copy: "Copy" }
    }
    var symbol: String {
        switch self { case .translate: "character.bubble"; case .notes: "note.text"; case .copy: "doc.on.doc" }
    }
    static func available(notes: Bool) -> [Self] { notes ? allCases : [.translate, .copy] }
    static func destination(at point: CGPoint, content: CGRect, notes: Bool) -> Self? {
        guard content.contains(point), content.width > 0 else { return nil }
        let actions = available(notes: notes)
        return actions[min(actions.count - 1, Int((point.x - content.minX) / content.width * CGFloat(actions.count)))]
    }
}

enum TextDropReader {
    @MainActor static func text(from pasteboard: NSPasteboard) -> String? {
        // Files, images and browser download links retain their existing drop actions.
        guard !FileDropReader.canReadFiles(from: pasteboard), let value = pasteboard.string(forType: .string) else { return nil }
        return clean(value)
    }
    static func clean(_ text: String) -> String? {
        guard text.utf8.count <= 1024 * 1024 else { return nil }
        let value = text.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    static func translationURL(_ text: String, language: String = Locale.current.language.languageCode?.identifier ?? "en") -> URL? {
        var url = URLComponents(string: "https://translate.google.com/")!
        url.queryItems = [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: language),
                          URLQueryItem(name: "op", value: "translate"), URLQueryItem(name: "text", value: String(text.prefix(5000)))]
        return url.url
    }
}
