//
//  WelcomeExperience.swift
//  Jonwork
//
//  Created by ChatGPT on 2025/12/08.
//

import Foundation

enum WelcomeExperience {
    private static let seenVersionKey = "WelcomeExperience.lastSeenVersion"

    private static var currentVersion: String {
        "jonwork-onboarding-1"
    }

    static var shouldPresent: Bool {
        shouldPresent(in: .standard)
    }

    static func shouldPresent(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: seenVersionKey) != currentVersion
    }

    static func markPresented(in defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: seenVersionKey)
    }
}
