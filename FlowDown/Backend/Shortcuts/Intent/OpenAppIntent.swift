//
//  OpenAppIntent.swift
//  FlowDown
//
//  Created by qaq on 8/11/2025.
//

import AppIntents
import Foundation

struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Open FlowDown"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Launch FlowDown without performing any additional actions."),
            categoryName: LocalizedStringResource("Utilities"),
        )
    }

    static var openAppWhenRun: Bool {
        true
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open FlowDown")
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
