@testable import Jonwork
import Foundation
import ImageIO
import UIKit
import Testing

struct MarkdownOutputImagesTests {
    @Test func parsesNestedAndReferenceImagesWithoutCodeOrLinkFalsePositives() {
        let markdown = """
        **![Chart](https://cdn.example.com/chart.png)**
        ![Again](https://cdn.example.com/chart.png)
        ![Reference][plot]

        [plot]: https://cdn.example.com/plot.png

        [Link](https://cdn.example.com/not-an-image.png)
        `![Code](https://cdn.example.com/code.png)`
        """
        #expect(MarkdownOutputImages.urls(in: markdown).map(\.lastPathComponent) == ["chart.png", "plot.png"])
    }

    @Test func refusesUnsafeAndCredentialURLs() {
        for source in ["http://example.com/a.png", "file:///tmp/a.png", "data:image/png;base64,abc",
                       "https://name:password@example.com/a.png", "https://localhost/a.png",
                       "https://127.0.0.1/a.png", "https://device.local/a.png", "https://example.com:8443/a.png"] {
            #expect(MarkdownOutputImages.allowedURL(source) == nil)
        }
        #expect(MarkdownOutputImages.allowedURL("https://cdn.example.com/a.png?signature=opaque") != nil)
    }

    @Test func capsImageCountAndIgnoresIncompleteMarkdown() {
        let markdown = (0 ..< 20).map { "![Image](https://example.com/\($0).png)" }.joined(separator: "\n")
        #expect(MarkdownOutputImages.urls(in: markdown).count == 4)
        #expect(MarkdownOutputImages.urls(in: "![Image](https://example.com/incomplete").isEmpty)
    }

    @Test func downloadsImageWithoutCredentialsAndCreatesThumbnail() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let data = try await MarkdownOutputImages.load(URL(string: "https://fixture.example.com/valid")!, configuration: configuration)
        #expect(!data.isEmpty)
        #expect(MarkdownOutputImages.thumbnail(data) != nil)
    }

    @MainActor
    @Test func previewExtensionMatchesEncodedJPEGInsteadOfURLOrThumbnail() throws {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.9))
        #expect(["jpg", "jpeg"].contains(try #require(MarkdownOutputImages.filenameExtension(jpeg))))
        let thumbnail = try #require(MarkdownOutputImages.thumbnail(jpeg))
        #expect(MarkdownOutputImages.filenameExtension(thumbnail) == "png")
        #expect(MarkdownOutputImages.filenameExtension(Data("invalid".utf8)) == nil)
    }

    @Test func rejectsNonImageResponseAndOversizedDeclaredLength() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        for name in ["html", "oversized", "redirect", "too-large-body"] {
            do {
                _ = try await MarkdownOutputImages.load(URL(string: "https://fixture.example.com/\(name)")!, configuration: configuration)
                Issue.record("Invalid image response was accepted")
            } catch {}
        }
    }
}

private final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url!.lastPathComponent
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let body: Data = if name == "valid" {
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
        } else if name == "too-large-body" {
            Data(repeating: 0, count: MarkdownOutputImages.maximumBytes + 1)
        } else { Data() }
        var headers = [
            "Content-Type": name == "html" ? "text/html" : "image/png",
            "Content-Length": name == "oversized" ? "999999999" : String(body.count),
        ]
        if name == "too-large-body" { headers.removeValue(forKey: "Content-Length") }
        let response = HTTPURLResponse(url: request.url!, statusCode: name == "redirect" ? 302 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
