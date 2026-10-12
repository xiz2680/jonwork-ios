import AppIntents

struct Shortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .lime
    }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateResponseIntent(),
            phrases: [
                "Ask Model on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Ask Model"),
            systemImageName: "text.bubble",
        )

        AppShortcut(
            intent: SetConversationModelIntent(),
            phrases: [
                "Set conversation model on \(.applicationName)",
                "Set default model on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Set Model"),
            systemImageName: "slider.horizontal.3",
        )

        AppShortcut(
            intent: GenerateNewConversationLinkIntent(),
            phrases: [
                "Create FlowDown link on \(.applicationName)",
                "New conversation link on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Conversation Link"),
            systemImageName: "link",
        )

        AppShortcut(
            intent: ClassifyContentIntent(),
            phrases: [
                "Classify content on \(.applicationName)",
                "Classify with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Classify"),
            systemImageName: "checklist",
        )

        AppShortcut(
            intent: SearchConversationsIntent(),
            phrases: [
                "Search conversations on \(.applicationName)",
                "Find chats on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Search Chats"),
            systemImageName: "magnifyingglass",
        )

        AppShortcut(
            intent: CreateNewConversationIntent(),
            phrases: [
                "Create new conversation on \(.applicationName)",
                "New chat on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("New Conversation"),
            systemImageName: "plus.message",
        )

        AppShortcut(
            intent: FillConversationMessageIntent(),
            phrases: [
                "Fill message on \(.applicationName)",
                "Add content to conversation on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Fill Message"),
            systemImageName: "pencil.and.list.clipboard",
        )

        AppShortcut(
            intent: ShowConversationIntent(),
            phrases: [
                "Show conversation on \(.applicationName)",
                "Open chat on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Show Conversation"),
            systemImageName: "bubble.left",
        )

        AppShortcut(
            intent: ShowAndSendConversationIntent(),
            phrases: [
                "Send conversation on \(.applicationName)",
                "Show and send on \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Show & Send"),
            systemImageName: "paperplane.circle",
        )

        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: [
                "Translate text on \(.applicationName)",
                "Translate with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Translate"),
            systemImageName: "globe",
        )
    }
}
