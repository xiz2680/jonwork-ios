import AppIntents
import Foundation

enum TranslationLanguage: String, AppEnum, CaseIterable {
    case arabic = "العربية"
    case polish = "Polski"
    case german = "Deutsch"
    case russian = "Русский"
    case french = "Français"
    case korean = "한국어"
    case dutch = "Nederlands"
    case portugueseBrazil = "Português (Brasil)"
    case japanese = "日本語"
    case thai = "ไทย"
    case turkish = "Türkçe"
    case ukrainian = "Українська"
    case spanishSpain = "Español (España)"
    case italian = "Italiano"
    case hindi = "हिन्दी"
    case indonesian = "Bahasa Indonesia"
    case englishUS = "English (US)"
    case englishUK = "English (UK)"
    case vietnamese = "Tiếng Việt"
    case chineseTraditional = "繁體中文"
    case chineseSimplified = "简体中文"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Language")
    }

    static var caseDisplayRepresentations: [TranslationLanguage: DisplayRepresentation] {
        [
            .arabic: "العربية",
            .polish: "Polski",
            .german: "Deutsch",
            .russian: "Русский",
            .french: "Français",
            .korean: "한국어",
            .dutch: "Nederlands",
            .portugueseBrazil: "Português (Brasil)",
            .japanese: "日本語",
            .thai: "ไทย",
            .turkish: "Türkçe",
            .ukrainian: "Українська",
            .spanishSpain: "Español (España)",
            .italian: "Italiano",
            .hindi: "हिन्दी",
            .indonesian: "Bahasa Indonesia",
            .englishUS: "English (US)",
            .englishUK: "English (UK)",
            .vietnamese: "Tiếng Việt",
            .chineseTraditional: "繁體中文",
            .chineseSimplified: "简体中文",
        ]
    }
}

struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Translate Text"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Translate text into a target language using a selected model."),
            categoryName: LocalizedStringResource("Translation"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Text", requestValueDialog: "What text should be translated?")
    var text: String

    @Parameter(title: "Target Language")
    var targetLanguage: TranslationLanguage

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Translate \(\.$text) into \(\.$targetLanguage)") {
                \.$model
                \.$text
                \.$targetLanguage
            }
        } otherwise: {
            Summary("Translate \(\.$text) into \(\.$targetLanguage) using the default model") {
                \.$model
                \.$text
                \.$targetLanguage
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShortcutError.emptyMessage }

        let language = targetLanguage.rawValue
        let directive =
            """
            You are a professional translator. Your task is to translate the input text into \(language).

            Strict Rules:
            1. **Line-by-Line Correspondence**: The translated output must have exactly the same number of lines as the source text. Do not merge or split lines.
            2. **Pure Output**: Output ONLY the translated result. No explanations, no "Here is the translation", no quotes.
            3. **Plain Text**: Do NOT use Markdown, XML tags, or any special formatting.
            4. **Empty Lines**: If a specific line in the source is empty, keep it empty in the translation.

            The text to translate will be provided as the user message.
            """

        let message = [
            directive,
            "",
            "---",
            trimmed,
        ].joined(separator: "\n")

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: nil,
            audio: nil,
            options: .init(allowsImages: false),
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}
