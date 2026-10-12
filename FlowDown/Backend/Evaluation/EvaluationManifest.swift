//
//  EvaluationManifest.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import Foundation

class EvaluationManifest: Codable {
    var title: String.LocalizationValue
    var description: String.LocalizationValue
    var suites: [Suite]

    init(title: String.LocalizationValue, description: String.LocalizationValue, suites: [Suite]) {
        self.title = title
        self.description = description
        self.suites = suites
    }
}

extension EvaluationManifest {
    func manifestExcludingSuites(_ list: [Suite.ID], casesList: [Suite.Case.ID]) -> EvaluationManifest? {
        let excludeList: Set<Suite.ID> = .init(list)
        let copiedSuites = suites
            .compactMap { $0.suiteExcludingCases(casesList) }
            .filter { !excludeList.contains($0.id) }
        if copiedSuites.isEmpty { return nil }
        return EvaluationManifest(
            title: title,
            description: description,
            suites: copiedSuites,
        )
    }
}

extension EvaluationManifest {
    static var baseCapabilities: EvaluationManifest {
        EvaluationManifest(
            title: "Base Capabilities",
            description: "Fundamental capabilities including instruction following and tool usage.",
            suites: [
                .instructionFollowing,
                .toolCalling,
            ],
        )
    }

    static var programming: EvaluationManifest {
        EvaluationManifest(
            title: "Programming",
            description: "Code generation capabilities across multiple languages.",
            suites: [
                .programmingC,
                .programmingPython,
                .programmingGo,
                .programmingSwift,
                .programmingWeb,
                .programmingRust,
            ],
        )
    }

    static var all: [EvaluationManifest] {
        [baseCapabilities, programming]
    }
}
