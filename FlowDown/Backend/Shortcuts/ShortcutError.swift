//
//  ShortcutError.swift
//  FlowDown
//
//  Created by qaq on 7/11/2025.
//

import AppIntents
import Foundation

enum ShortcutError: LocalizedError {
    case unavailable
    case emptyMessage
    case modelUnavailable
    case emptyResponse
    case imageNotAllowed
    case imageNotSupportedByModel
    case invalidImage
    case audioNotAllowed
    case audioNotSupportedByModel
    case invalidAudio
    case invalidCandidates

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "This shortcut is unavailable in Jonwork.")
        case .emptyMessage:
            String(localized: "Empty message.")
        case .modelUnavailable:
            String(localized: "Unable to find the selected model.")
        case .emptyResponse:
            String(localized: "The model did not return any content.")
        case .imageNotAllowed:
            String(localized: "This shortcut does not accept images.")
        case .imageNotSupportedByModel:
            String(localized: "The selected model does not support image inputs.")
        case .invalidImage:
            String(localized: "The provided image could not be processed.")
        case .audioNotAllowed:
            String(localized: "This shortcut does not accept audio.")
        case .audioNotSupportedByModel:
            String(localized: "The selected model does not support audio inputs.")
        case .invalidAudio:
            String(localized: "The provided audio could not be processed.")
        case .invalidCandidates:
            String(localized: "At least one candidate is required.")
        }
    }
}

enum ShortcutAvailability {
    static var legacyActionsEnabled: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    static func performLegacyAction<T>(
        enabled: Bool = legacyActionsEnabled,
        _ action: () throws -> T
    ) throws -> T {
        guard enabled else { throw ShortcutError.unavailable }
        return try action()
    }
}
