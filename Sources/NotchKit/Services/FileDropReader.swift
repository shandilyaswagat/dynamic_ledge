import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum FileDropReader {
    private static let promisedContent = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private static let imageTypes: [NSPasteboard.PasteboardType] =
        [.png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.gif.identifier), .init(UTType.webP.identifier)]
    static let draggedTypes = promiseTypes + imageTypes + [.fileURL, .URL, .string, .init("NSFilenamesPboardType")]

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

    /// Chromium can expose the promised file's UTI and original bytes on the same item.
    static func promisedBytes(from pasteboard: NSPasteboard, source: URL?) -> Image? {
        for item in pasteboard.pasteboardItems ?? [] {
            guard let identifier = item.string(forType: promisedContent), identifier.count < 256,
                  let type = UTType(identifier), type.conforms(to: .data), !type.conforms(to: .url),
                  let data = item.data(forType: .init(identifier)), !data.isEmpty,
                  data.count <= WebDropDownload.maximumBytes else { continue }
            let sourceExtension = source?.pathExtension ?? ""
            let ext = type.preferredFilenameExtension ?? (sourceExtension.isEmpty ? "bin" : sourceExtension)
            let name = source?.deletingPathExtension().lastPathComponent ?? ""
            return Image(data: data, name: name.isEmpty ? "Dropped File" : name, ext: ext)
        }
        return nil
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
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let supported = urls.filter(DropPolicy.isSupported)
            if !supported.isEmpty { return supported }
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
        if !paths.isEmpty { return paths.map { URL(fileURLWithPath: $0) } }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace), let url = URL(string: text), WebDropDownload.canFetch(url) else { return [] }
        return [url]
    }
}
