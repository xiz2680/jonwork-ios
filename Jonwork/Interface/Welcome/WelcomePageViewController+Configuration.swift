import UIKit

extension WelcomePageViewController {
    struct Configuration {
        var pages: [Page]
        var nextButtonTitle: String.LocalizationValue
        var finalButtonTitle: String.LocalizationValue
    }

    struct Page {
        var symbol: String
        var title: String.LocalizationValue
        var subtitle: String.LocalizationValue
        var accentColor: UIColor
    }

    struct Feature {
        var icon: UIImage
        var title: String.LocalizationValue
        var detail: String.LocalizationValue
    }
}

extension WelcomePageViewController.Configuration {
    static var `default`: Self {
        .init(
            pages: [
                .init(
                    symbol: "JonworkHeroJ",
                    title: "Move ideas forward",
                    subtitle: "Start with a conversation. Let the work move naturally.",
                    accentColor: JonworkPastelBackgroundView.accent
                ),
                .init(
                    symbol: "waveform.path.ecg.rectangle.fill",
                    title: "Work in motion",
                    subtitle: "Answers and tools, together in one clear timeline.",
                    accentColor: JonworkPastelBackgroundView.accent
                ),
                .init(
                    symbol: "lock.shield.fill",
                    title: "Your workspace, ready",
                    subtitle: "Sign in once. Approved work appears automatically.",
                    accentColor: JonworkPastelBackgroundView.accent
                ),
            ],
            nextButtonTitle: "Continue",
            finalButtonTitle: "Sign In"
        )
    }
}
