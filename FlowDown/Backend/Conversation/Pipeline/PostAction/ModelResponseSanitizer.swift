import Foundation

enum ModelResponseSanitizer {
    private static let reasoningPatterns: [NSRegularExpression] = {
        let rawPatterns = [
            "(?is)<think>.*?</think>",
            "(?is)<thinking>.*?</thinking>",
            "(?is)<reasoning>.*?</reasoning>",
            "(?is)<think>.*",
            "(?is)<thinking>.*",
            "(?is)<reasoning>.*",
        ]

        return rawPatterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [])
        }
    }()

    static func stripReasoning(from text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = text

        for regex in reasoningPatterns {
            let range = NSRange(sanitized.startIndex ..< sanitized.endIndex, in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "",
            )
        }

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
