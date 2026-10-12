@testable import FlowDown
import Testing

struct ConversationScopeTests {
    @Test
    func `model response sanitizer removes reasoning tags and trailing reasoning`() {
        let wrappedReasoning = """
        Final answer
        <think>hidden chain of thought</think>
        Visible conclusion
        """
        let trailingReasoning = "Visible answer<thinking>more hidden reasoning"

        let sanitizedWrapped = ModelResponseSanitizer.stripReasoning(from: wrappedReasoning)
        let sanitizedTrailing = ModelResponseSanitizer.stripReasoning(from: trailingReasoning)

        #expect(sanitizedWrapped.contains("Final answer"))
        #expect(sanitizedWrapped.contains("Visible conclusion"))
        #expect(!sanitizedWrapped.contains("hidden chain of thought"))
        #expect(sanitizedTrailing == "Visible answer")
    }

    @Test
    func `rewrite actions expose non empty prompts titles and icons`() {
        #expect(RewriteAction.allCases.count == 6)

        for action in RewriteAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.prompt.isEmpty)
            #expect(action.icon != nil)
        }
    }

    @Test
    func `conversation metadata parser decodes title and icon from xml`() {
        let xml = """
        <conversation>
            <title>Kyoto trip plan</title>
            <icon>⛩️</icon>
        </conversation>
        """

        let metadata = ConversationMetadataParser.parseXML(xml)

        #expect(metadata == ConversationMetadata(title: "Kyoto trip plan", icon: "⛩️"))
    }

    @Test
    func `conversation metadata parser strips reasoning before decoding`() {
        let response = """
        <think>hidden reasoning</think>
        <conversation>
            <title>**Launch checklist**</title>
            <icon>🚀</icon>
        </conversation>
        """

        let metadata = ConversationMetadataParser.parseResponse(response)

        #expect(metadata == ConversationMetadata(title: "Launch checklist", icon: "🚀"))
    }

    @Test
    func `conversation metadata parser supports partial xml payloads`() {
        let titleOnlyXML = """
        <conversation>
            <title>Budget review notes</title>
        </conversation>
        """

        let metadata = ConversationMetadataParser.parseXML(titleOnlyXML)

        #expect(metadata == ConversationMetadata(title: "Budget review notes", icon: nil))
    }

    @Test
    func `conversation metadata parser preserves title normalization rules`() {
        let normalized = ConversationMetadataParser.normalizedTitle(
            "**1234567890123456789012345678901234567890**",
        )

        #expect(normalized == "12345678901234567890123456789012")
    }

    @Test
    func `conversation metadata parser extracts first emoji from verbose icon response`() {
        let normalized = ConversationMetadataParser.normalizedIcon("Status ✅ complete")

        #expect(normalized == "✅")
    }
}
