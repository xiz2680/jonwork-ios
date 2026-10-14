import Foundation
import ImageIO
import MarkdownParser
import UniformTypeIdentifiers

/// Credential-free HTTPS Markdown image downloads. Gateway credentials are never used here.
enum MarkdownOutputImages {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumImages = 4

    static func allowedURL(_ source: String) -> URL? {
        guard let url = URL(string: source), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !host.contains(":"), host.contains(where: { $0.isLetter }),
              url.port == nil || url.port == 443
        else { return nil }
        return url
    }

    static func urls(in markdown: String) -> [URL] {
        var result: [URL] = []
        func visitInline(_ nodes: [MarkdownInlineNode]) {
            for node in nodes {
                switch node {
                case let .image(source, _):
                    if result.count < maximumImages, let url = allowedURL(source), !result.contains(url) {
                        result.append(url)
                    }
                case let .emphasis(children), let .strong(children), let .strikethrough(children), let .link(_, children):
                    visitInline(children)
                default: break
                }
            }
        }
        func visit(_ blocks: [MarkdownBlockNode]) {
            for block in blocks {
                switch block {
                case let .blockquote(children): visit(children)
                case let .bulletedList(_, items): items.forEach { visit($0.children) }
                case let .taskList(_, items): items.forEach { visit($0.children) }
                case let .numberedList(_, _, items): items.forEach { visit($0.children) }
                case let .paragraph(content), let .heading(_, content): visitInline(content)
                case let .table(_, rows): rows.forEach { $0.cells.forEach { visitInline($0.content) } }
                case .codeBlock, .thematicBreak: break
                }
            }
        }
        visit(MarkdownParser().parse(markdown).document)
        return result
    }

    static func load(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        guard allowedURL(url.absoluteString) != nil else { throw URLError(.badURL) }
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("image/png,image/jpeg,image/webp,image/gif", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= maximumBytes
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 24_000_000
        else { throw URLError(.cannotDecodeContentData) }
        return data
    }

    static func filenameExtension(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image)
        else { return nil }
        return type.preferredFilenameExtension
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
                        newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
