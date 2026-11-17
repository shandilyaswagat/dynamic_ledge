import Foundation
import UniformTypeIdentifiers

/// One user-dropped URL. Delegate state is accessed only on the session's serial delegate queue.
final class WebDropDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome: Sendable { case file(URL), link, failed }
    static let maximumBytes = 64 * 1024 * 1024

    private let directory: URL
    private let completion: @Sendable (Outcome) -> Void
    private var destination: URL?
    private var handle: FileHandle?
    private var received = 0
    private var outcome: Outcome = .failed

    private init(directory: URL, completion: @escaping @Sendable (Outcome) -> Void) {
        self.directory = directory
        self.completion = completion
    }

    static func canFetch(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    static func fetch(_ url: URL, into directory: URL, configuration: URLSessionConfiguration = .ephemeral,
                      completion: @escaping @Sendable (Outcome) -> Void) -> URLSessionDataTask {
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        let delegate = WebDropDownload(directory: directory, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: url)
        task.resume()
        return task
    }

    /// A page remains a shortcut. Attachments and direct file responses become files.
    static func filename(for response: HTTPURLResponse) -> String? {
        let mime = response.mimeType?.lowercased()
        let attachment = response.value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
        let urlExtension = response.url?.pathExtension.lowercased() ?? ""
        if !attachment {
            guard let mime, !["text/html", "application/xhtml+xml"].contains(mime) else { return nil }
            if mime == "text/plain", urlExtension.isEmpty { return nil }
        }
        let type = mime.flatMap { UTType(mimeType: $0) }
        var proposed = response.suggestedFilename ?? response.url?.lastPathComponent ?? ""
        if proposed.isEmpty || proposed == "Unknown" { proposed = "Dropped File" }
        if (proposed as NSString).pathExtension.isEmpty, let extensionName = type?.preferredFilenameExtension {
            proposed += "." + extensionName
        }
        return safeName(proposed)
    }

    static func safeName(_ value: String) -> String {
        let basename = value.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let clean = String(basename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !clean.isEmpty else { return "Dropped File" }
        let extensionName = (clean as NSString).pathExtension
        let stem = (clean as NSString).deletingPathExtension
        return String(stem.unicodeScalars.prefix(48)) + (extensionName.isEmpty ? "" : "." + String(extensionName.unicodeScalars.prefix(12)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.canFetch) == true ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            return
        }
        guard let name = Self.filename(for: http) else {
            outcome = .link
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else {
            completionHandler(.cancel)
            return
        }
        let file = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        guard let writer = try? FileHandle(forWritingTo: file) else { completionHandler(.cancel); return }
        destination = file
        handle = writer
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handle, data.count <= Self.maximumBytes - received else {
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
            received += data.count
        } catch { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let closed = (try? handle?.close()) != nil
        handle = nil
        if error == nil, closed, let destination { outcome = .file(destination) }
        completion(outcome)
        session.finishTasksAndInvalidate()
    }
}
