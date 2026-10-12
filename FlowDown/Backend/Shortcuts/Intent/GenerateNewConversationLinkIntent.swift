import AppIntents
import Foundation

struct GenerateNewConversationLinkIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Create Conversation Link"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Create a deep link that starts a new conversation in the app."),
            categoryName: LocalizedStringResource("Utilities"),
        )
    }

    @Parameter(title: "Initial Message", default: "", requestValueDialog: "What message should we pre-fill?")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create a link to present \(\.$message) in app") {
            \.$message
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialMessage = trimmedMessage.isEmpty == false ? trimmedMessage : nil

        let url = try ShortcutUtilities.newConversationURL(initialMessage: initialMessage)
        let link = url.absoluteString

        let dialogMessage = String(
            localized: "Use the Open URL action with \(link) to launch the app and start a conversation",
        )

        let dialog = IntentDialog(.init(stringLiteral: dialogMessage))
        return .result(value: link, dialog: dialog)
    }
}
