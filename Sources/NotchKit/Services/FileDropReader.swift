import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum FileDropReader {
    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private static let imageTypes: [NSPasteboard.PasteboardType] =
        [.png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.gif.identifier), .init(UTType.webP.identifier)]
    static let draggedTypes = promiseTypes + imageTypes + [.fileURL, .URL, .init("NSFilenamesPboardType")]

    static func canReadFiles(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: promiseTypes + imageTypes) != nil || !urls(from: pasteboard).isEmpty
    }

    static func promises(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        guard pasteboard.availableType(from: promiseTypes) != nil else { return [] }
        return pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
    }

    struct Image {
        let data: Data
        let name: String
        let ext: String
    }

    static func image(from pasteboard: NSPasteboard, source: URL?) -> Image? {
        for type in imageTypes {
            guard let data = pasteboard.data(forType: type), data.count <= 64 * 1024 * 1024,
                  let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let identifier = CGImageSourceGetType(image), let ext = UTType(identifier as String)?.preferredFilenameExtension,
                  CGImageSourceGetCount(image) > 0 else { continue }
            let name = source?.deletingPathExtension().lastPathComponent ?? ""
            return Image(data: data, name: name.isEmpty || name == "/" ? "Dropped Image" : name, ext: ext)
        }
        return nil
    }

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
