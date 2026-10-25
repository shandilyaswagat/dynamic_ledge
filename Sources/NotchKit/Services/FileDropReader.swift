import AppKit

@MainActor
enum FileDropReader {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls.filter(DropPolicy.isSupported)
        }
        let urls = (pasteboard.pasteboardItems ?? []).compactMap { item -> URL? in
            for type in [NSPasteboard.PasteboardType.fileURL, .URL] {
                if let text = item.string(forType: type), let url = URL(string: text), DropPolicy.isSupported(url) {
                    return url
                }
            }
            return nil
        }
        if !urls.isEmpty { return urls }
        let paths = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }
}
