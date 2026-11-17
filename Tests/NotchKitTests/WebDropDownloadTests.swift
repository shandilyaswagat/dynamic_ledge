import Foundation
import Testing
@testable import NotchKit

@Suite("Web file drops")
struct WebDropDownloadTests {
    @Test(arguments: ["attachment", "page", "too-large"])
    func readsAFileOrRetainsTheLink(kind: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DropResponse.self]
        let url = try #require(URL(string: "https://example.invalid/\(kind)"))
        let result = await withCheckedContinuation { continuation in
            _ = WebDropDownload.fetch(url, into: folder, configuration: configuration) { result in
                continuation.resume(returning: result)
            }
        }
        switch (kind, result) {
        case ("attachment", .file(let file)):
            #expect(file.lastPathComponent == "report.pdf")
            #expect(try Data(contentsOf: file) == DropResponse.contents)
        case ("page", .link), ("too-large", .failed):
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        default: Issue.record("Unexpected drop result: \(result)")
        }
    }

    @Test func normalizesBrowserFileNames() {
        #expect(WebDropDownload.safeName("../safe file.pdf") == "safe file.pdf")
        #expect(WebDropDownload.safeName("site\\nested\\report.pdf") == "report.pdf")
        #expect(WebDropDownload.safeName("..") == "Dropped File")
    }
}

private final class DropResponse: URLProtocol, @unchecked Sendable {
    static let contents = Data("test attachment".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let headers: [String: String]
        switch url.lastPathComponent {
        case "attachment":
            headers = ["Content-Type": "application/pdf", "Content-Disposition": "attachment; filename=report.pdf"]
        case "too-large":
            headers = ["Content-Type": "application/pdf", "Content-Length": String(WebDropDownload.maximumBytes + 1)]
        default:
            headers = ["Content-Type": "text/html"]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.contents)
        client?.urlProtocolDidFinishLoading(self)
    }
}
