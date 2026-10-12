//
//  EvaluationOptions.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import Foundation

class EvaluationOptions: Codable {
    /// model to be tested later
    let modelIdentifier: ModelManager.ModelIdentifier

    // what to test, and we store the result and outcome inside each case
    var manifesets: [EvaluationManifest]
    var excludedSuites: [EvaluationManifest.Suite.ID] = []
    var excludedCases: [EvaluationManifest.Suite.Case.ID] = []

    struct Options: Codable {
        var maxConcurrentRequests: Int = 8
        var shots: Int = 2
    }

    var options: Options

    init(
        modelIdentifier: ModelManager.ModelIdentifier,
        manifesets: [EvaluationManifest] = EvaluationManifest.all,
        excludedSuites: [EvaluationManifest.Suite.ID] = [],
        excludedCases: [EvaluationManifest.Suite.Case.ID] = [],
        options: Options = .init(),
    ) {
        self.modelIdentifier = modelIdentifier
        self.manifesets = manifesets
        self.excludedSuites = excludedSuites
        self.excludedCases = excludedCases
        self.options = options
    }
}

extension EvaluationOptions {
    func createFinalManifest() -> [EvaluationManifest] {
        manifesets.compactMap {
            $0.manifestExcludingSuites(excludedSuites, casesList: excludedCases)
        }
    }
}
