//
//  EvaluationMenuFactory.swift
//  FlowDown
//
//  Created by qaq on 19/12/2025.
//

import UIKit

enum EvaluationMenuFactory {
    static func makeMenu(
        session: EvaluationSession,
        caseItem: EvaluationManifest.Suite.Case,
        onUpdate: @escaping () -> Void = {},
    ) -> UIMenu {
        let currentOutcome = caseItem.results.last?.outcome ?? .notDetermined

        let markSuccess = UIAction(
            title: String(localized: "Mark as Success"),
            image: UIImage(systemName: "checkmark.circle"),
            attributes: [],
        ) { _ in
            Task {
                await updateOutcome(session: session, caseItem: caseItem, outcome: .pass)
                await MainActor.run {
                    onUpdate()
                }
            }
        }

        let markFailure = UIAction(
            title: String(localized: "Mark as Failure"),
            image: UIImage(systemName: "xmark.circle"),
            attributes: [],
        ) { _ in
            Task {
                await updateOutcome(session: session, caseItem: caseItem, outcome: .fail)
                await MainActor.run {
                    onUpdate()
                }
            }
        }

        let reRun = UIAction(
            title: String(localized: "Re-run"),
            image: UIImage(systemName: "arrow.clockwise"),
            attributes: [],
        ) { _ in
            Task {
                await reRunCase(session: session, caseItem: caseItem)
                await MainActor.run {
                    onUpdate()
                }
            }
        }

        let delete = UIAction(
            title: String(localized: "Delete"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { _ in
            Task {
                await deleteCase(session: session, caseItem: caseItem)
                await MainActor.run {
                    onUpdate()
                }
            }
        }

        let markActions: [UIAction] = switch currentOutcome {
        case .pass:
            [markFailure]
        case .fail:
            [markSuccess]
        case .notDetermined, .processing, .awaitingJudging:
            [markSuccess, markFailure]
        }

        return UIMenu(title: "", children: markActions + [reRun, delete])
    }

    private static func updateOutcome(
        session: EvaluationSession,
        caseItem: EvaluationManifest.Suite.Case,
        outcome: EvaluationManifest.Suite.Case.Result.Outcome,
    ) async {
        if let lastResult = caseItem.results.last {
            lastResult.outcome = outcome
        } else {
            // Should not happen usually, but if so create one
            let result = EvaluationManifest.Suite.Case.Result(outcome: outcome)
            caseItem.results.append(result)
        }
        saveAndNotify(session: session)
    }

    private static func reRunCase(
        session: EvaluationSession,
        caseItem: EvaluationManifest.Suite.Case,
    ) async {
        // Prepare for re-run: set outcome to notDetermined
        if let lastResult = caseItem.results.last {
            lastResult.outcome = .notDetermined
        } else {
            let result = EvaluationManifest.Suite.Case.Result(outcome: .notDetermined)
            caseItem.results.append(result)
        }

        // Ensure session is running
        session.resume()
        saveAndNotify(session: session)
    }

    private static func deleteCase(
        session: EvaluationSession,
        caseItem: EvaluationManifest.Suite.Case,
    ) async {
        for manifest in session.manifests {
            for suite in manifest.suites {
                if let index = suite.cases.firstIndex(where: { $0.id == caseItem.id }) {
                    suite.cases.remove(at: index)
                    saveAndNotify(session: session)
                    return
                }
            }
        }
    }

    private static func saveAndNotify(session: EvaluationSession) {
        // Save logic
        _ = try? EvaluationSessionManager.shared.save(session)
        // Notify on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .evaluationSessionDidUpdate, object: session)
        }
    }
}
