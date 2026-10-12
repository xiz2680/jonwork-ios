//
//  WidgetsAttributes.swift
//  FlowDown
//
//  Created by qaq on 7/1/2026.
//

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)

    import ActivityKit
    import Foundation

    struct FlowDownWidgetsAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            var runningSession: Int
            var incomingTokens: Int

            // Preferred field names for app-side packaging.
            var conversationCount: Int
            var streamingSessionTextCount: Int
        }
    }

#endif
