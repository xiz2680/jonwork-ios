@testable import FlowDown
import Foundation
import Testing

struct SupplementScopeTests {
    @Test
    func `chat selection exposes identifiers and options from selections`() {
        let identifier = "conversation-id"
        let options: ChatSelection.Options = [.collapseSidebar, .focusEditor]
        let selection = ChatSelection.Selection.conversation(id: identifier, options: options)

        #expect(selection.identifier == identifier)
        #expect(selection.options.contains(.collapseSidebar))
        #expect(selection.options.contains(.focusEditor))
        #expect(ChatSelection.Selection.none.identifier == nil)
        #expect(ChatSelection.Selection.none.options == .none)
    }

    @Test
    func `disposable exporter writes temporary file resources for sharing`() throws {
        let name = UUID().uuidString
        let expectedURL = disposableResourcesDir
            .appendingPathComponent(name)
            .appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: expectedURL)

        _ = DisposableExporter(
            data: Data("hello exporter".utf8),
            name: name,
            pathExtension: "txt",
        )

        #expect(FileManager.default.fileExists(atPath: expectedURL.path))
        #expect(try String(contentsOf: expectedURL, encoding: .utf8) == "hello exporter")

        try? FileManager.default.removeItem(at: expectedURL)
    }
}
