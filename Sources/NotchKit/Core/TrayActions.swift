import AppKit
import PDFKit

/// What the Tray can make from its files: one .zip of them, or one PDF of its PDFs and images.
/// Results are saved next to the first file (or in Downloads when that folder can't be written,
/// like a mounted disk image); originals are never changed.
public enum TrayActions {
    public enum Failure: Error, Equatable {
        case nothingToUse
        case failed
    }

    /// PDFs and images: what Merge PDF can use.
    public static func canMerge(_ url: URL) -> Bool {
        url.isFileURL && (url.pathExtension.lowercased() == "pdf" || FileConverter.isConvertible(url: url))
    }

    /// Compresses the files into one archive, like Finder's Compress: one item keeps its full name
    /// ("Report.pdf.zip"), several go into "Archive.zip".
    public static func zip(_ urls: [URL], fileManager: FileManager = .default) throws -> URL {
        let files = urls.filter { $0.isFileURL && fileManager.fileExists(atPath: $0.path) }
        guard let first = files.first else { throw Failure.nothingToUse }
        let folder = outputFolder(for: first, fileManager: fileManager)
        if files.count == 1 {
            let target = unique(in: folder, name: first.lastPathComponent, extension: "zip", fileManager: fileManager)
            try ditto([first.path, target.path])
            return target
        }
        // Several files, maybe from different folders: gather them (as clones, which take no
        // space on APFS) under one folder, then compress that.
        let staging = fileManager.temporaryDirectory.appendingPathComponent("DynamicLedge-Zip-" + UUID().uuidString)
        let archive = staging.appendingPathComponent("Archive", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        for file in files {
            let name = file.lastPathComponent
            let copy = unique(in: archive, name: (name as NSString).deletingPathExtension, extension: file.pathExtension, fileManager: fileManager)
            try fileManager.copyItem(at: file, to: copy)
        }
        let target = unique(in: folder, name: "Archive", extension: "zip", fileManager: fileManager)
        try ditto([archive.path, target.path])
        return target
    }

    /// Puts every page of the PDFs and every image, in order, into one PDF named "Merged.pdf".
    public static func mergePDF(_ urls: [URL], fileManager: FileManager = .default) throws -> URL {
        let files = urls.filter(canMerge)
        guard let first = files.first else { throw Failure.nothingToUse }
        let merged = PDFDocument()
        for file in files {
            if file.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: file), !document.isLocked else { continue }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index)?.copy() as? PDFPage {
                        merged.insert(page, at: merged.pageCount)
                    }
                }
            } else if let image = NSImage(contentsOf: file), let page = PDFPage(image: image) {
                merged.insert(page, at: merged.pageCount)
            }
        }
        guard merged.pageCount > 0 else { throw Failure.nothingToUse }
        let target = unique(in: outputFolder(for: first, fileManager: fileManager), name: "Merged", extension: "pdf", fileManager: fileManager)
        guard merged.write(to: target) else { throw Failure.failed }
        return target
    }

    /// The file's own folder, or Downloads when that can't be written.
    public static func outputFolder(for file: URL, fileManager: FileManager = .default) -> URL {
        let folder = file.deletingLastPathComponent()
        if fileManager.isWritableFile(atPath: folder.path) { return folder }
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
    }

    /// `name.ext`, or `name 2.ext` and so on if that's taken, as Finder names copies.
    static func unique(in folder: URL, name: String, extension ext: String, fileManager: FileManager) -> URL {
        func url(_ base: String) -> URL {
            let file = folder.appendingPathComponent(base)
            return ext.isEmpty ? file : file.appendingPathExtension(ext)
        }
        var candidate = url(name)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url("\(name) \(number)")
            number += 1
        }
        return candidate
    }

    /// Compresses with the same tool Finder uses, keeping the top folder's name.
    private static func ditto(_ paths: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"] + paths
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed }
    }
}
