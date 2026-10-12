import AppIntents
import Foundation
import UniformTypeIdentifiers

@available(iOS 18.0, macCatalyst 18.0, *)
struct TranscribeAudioIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Transcribe Audio"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Convert an audio recording into text using a model that supports audio input."),
            categoryName: LocalizedStringResource("Transcription"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: "Audio",
        supportedContentTypes: [.audio],
        requestValueDialog: "Which audio file should be transcribed?",
    )
    var audio: IntentFile

    @Parameter(
        title: "Language Hint",
        default: nil,
        requestValueDialog: "What language is primarily spoken?",
    )
    var languageHint: String?

    @Parameter(title: "Save to Conversation", default: false)
    var saveToConversation: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Transcribe the selected \(\.$audio) with the chosen model") {
                \.$model
                \.$audio
                \.$languageHint
                \.$saveToConversation
            }
        } otherwise: {
            Summary("Transcribe the selected \(\.$audio) with the default model") {
                \.$model
                \.$audio
                \.$languageHint
                \.$saveToConversation
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedHint = languageHint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        var instructions: [String.LocalizationValue] = [
            "You are a transcription assistant. Accurately transcribe the provided audio recording into written text with clear punctuation.",
            "Return only the transcription without additional commentary.",
        ]
        if let trimmedHint { instructions.append("The recording is primarily in \(trimmedHint).") }

        let message = instructions
            .map { String(localized: $0) }
            .joined(separator: " ")

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: nil,
            audio: audio,
            options: .init(
                allowsImages: false,
                allowsAudio: true,
                saveToConversation: saveToConversation,
            ),
        )

        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}
