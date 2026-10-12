//
//  EvaluationManifest+Case.Result.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import Foundation

extension EvaluationManifest.Suite.Case {
    class Result: Codable, Equatable {
        var output: [EvaluationManifest.Suite.Case.Content]
        var outcome: Outcome

        init(
            output: [EvaluationManifest.Suite.Case.Content] = [],
            outcome: Outcome = .notDetermined,
        ) {
            self.output = output
            self.outcome = outcome
        }

        static func == (lhs: EvaluationManifest.Suite.Case.Result, rhs: EvaluationManifest.Suite.Case.Result) -> Bool {
            lhs.outcome == rhs.outcome
                && lhs.output == rhs.output
        }
    }
}

extension EvaluationManifest.Suite.Case.Result {
    enum Outcome: String, Codable, Equatable {
        case notDetermined
        case processing
        case awaitingJudging
        case pass
        case fail
    }
}
