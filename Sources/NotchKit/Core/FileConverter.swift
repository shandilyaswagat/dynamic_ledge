import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff
    case webp
    case gif

    public var id: String { rawValue }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .webp: return .webP
        case .gif: return .gif
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    public var displayName: String {
        rawValue.uppercased()
    }
}

public enum FileConversionError: Error, LocalizedError {
    case unsupportedSourceFormat
    case failedToReadSource
    case failedToCreateDestination
    case conversionFailed
    case originalFileMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedSourceFormat: return String(localized: "This file format cannot be converted.")
        case .failedToReadSource: return String(localized: "Could not read the source file.")
        case .failedToCreateDestination: return String(localized: "Could not create the converted file destination.")
        case .conversionFailed: return String(localized: "File conversion failed.")
        case .originalFileMissing: return String(localized: "The original file could not be found.")
        }
    }
}

public enum FileConverter {
    public static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"
    ]

    public static func isConvertible(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedImageExtensions.contains(ext)
    }

    public static func availableExportFormats(for url: URL) -> [FileExportFormat] {
        guard isConvertible(url: url) else { return [] }
        let currentExt = url.pathExtension.lowercased()
        return FileExportFormat.allCases.filter { format in
            if format == .jpeg && (currentExt == "jpg" || currentExt == "jpeg") { return false }
            return format.rawValue != currentExt
        }
    }

    /// Converts an image to the requested format and writes the result to `destinationFolder`.
    /// Guarantees that the original file at `sourceURL` is never modified or removed.
    public static func convertImage(
        at sourceURL: URL,
        to format: FileExportFormat,
        destinationFolder: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileConversionError.originalFileMissing
        }
        guard isConvertible(url: sourceURL) else {
            throw FileConversionError.unsupportedSourceFormat
        }

        // Read source with ImageIO
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FileConversionError.failedToReadSource
        }

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var targetURL = destinationFolder.appendingPathComponent("\(baseName).\(format.fileExtension)")
        var counter = 1
        while fileManager.fileExists(atPath: targetURL.path) {
            targetURL = destinationFolder.appendingPathComponent("\(baseName)-\(counter).\(format.fileExtension)")
            counter += 1
        }

        // Never write to the source URL path
        if targetURL.path == sourceURL.path {
            targetURL = destinationFolder.appendingPathComponent("\(baseName)-converted.\(format.fileExtension)")
        }

        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw FileConversionError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: targetURL)
            throw FileConversionError.conversionFailed
        }

        return targetURL
    }
}
