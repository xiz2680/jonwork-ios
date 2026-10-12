import AppIntents
import Foundation

struct ClassifyContentIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Classify Content"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Use the model to classify content into one of the provided candidates. If the model cannot decide, the first candidate is returned."),
            categoryName: LocalizedStringResource("Classification"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What content should be classified?")
    var content: String

    @Parameter(title: "Candidate A", default: "")
    var candidateA: String

    @Parameter(title: "Candidate B", default: "")
    var candidateB: String

    @Parameter(title: "Candidate C", default: "")
    var candidateC: String

    @Parameter(title: "Candidate D", default: "")
    var candidateD: String

    private func makeManualCandidates() -> [String] {
        [
            candidateA,
            candidateB,
            candidateC,
            candidateD,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Use the selected model to classify your \(\.$content)") {
                \.$model
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        } otherwise: {
            Summary("Use the default model to classify your \(\.$content)") {
                \.$model
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw ShortcutError.emptyMessage
        }

        let resolvedCandidates = try CandidateInputResolver.resolveCandidates(
            manualCandidates: makeManualCandidates(),
        )

        let request = try ClassificationPromptBuilder.make(
            content: trimmedContent,
            candidates: resolvedCandidates,
            includeImageInstruction: false,
        )

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: request.message,
            image: nil,
            audio: nil,
            options: .init(allowsImages: false),
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

@available(iOS 18.0, macCatalyst 18.0, *)
struct ClassifyContentWithImageIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Classify Image"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Use the model to classify content with the help of an accompanying image. If the model cannot decide, the first candidate is returned."),
            categoryName: LocalizedStringResource("Classification"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Image", supportedContentTypes: [.image], requestValueDialog: "Select an image to accompany the request.")
    var image: IntentFile

    @Parameter(title: "Candidate A", default: "")
    var candidateA: String

    @Parameter(title: "Candidate B", default: "")
    var candidateB: String

    @Parameter(title: "Candidate C", default: "")
    var candidateC: String

    @Parameter(title: "Candidate D", default: "")
    var candidateD: String

    private func makeManualCandidates() -> [String] {
        [
            candidateA,
            candidateB,
            candidateC,
            candidateD,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Use the selected model to classify the image") {
                \.$model
                \.$image
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        } otherwise: {
            Summary("Use the default model to classify the image") {
                \.$model
                \.$image
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let resolvedCandidates = try CandidateInputResolver.resolveCandidates(
            manualCandidates: makeManualCandidates(),
        )

        let request = try ClassificationPromptBuilder.make(
            content: nil,
            candidates: resolvedCandidates,
            includeImageInstruction: true,
        )

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: request.message,
            image: image,
            audio: nil,
            options: .init(allowsImages: true),
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

private enum ClassificationPromptBuilder {
    struct Request {
        let message: String
        let sanitizedCandidates: [String]
        let primaryCandidate: String

        func resolveCandidate(from response: String) -> String {
            if let label = response.extractXMLLabelValue() {
                let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if let matchedCandidate = sanitizedCandidates.first(where: {
                    $0.compare(normalizedLabel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    return matchedCandidate
                }
            }

            let normalized = response
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
                ?? ""

            return sanitizedCandidates.first {
                $0.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            } ?? primaryCandidate
        }
    }

    static func make(
        content: String?,
        candidates: [String],
        includeImageInstruction: Bool,
    ) throws -> Request {
        let trimmedContent = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let sanitizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let primaryCandidate = sanitizedCandidates.first else {
            throw ShortcutError.invalidCandidates
        }

        let candidateList = sanitizedCandidates.enumerated()
            .map { index, value in
                // use xml tagging to help model better recognize the candidates
                let key = index + 1
                let keyText = "Label-\(key)"
                return "<\(keyText)>\(value)</\(keyText)>"
            }
            .joined(separator: "\n")

        var instructionSegments = [
            "You are a classification assistant. Choose the best candidate for the provided content.",
        ]

        if includeImageInstruction {
            instructionSegments.append(
                "An image is provided with this request. Consider the visual details when selecting the candidate.",
            )
        }

        instructionSegments.append(
            "An image is provided with this request. Consider the visual details when selecting the candidate.",
        )

        instructionSegments.append("Candidates:")
        instructionSegments.append(candidateList)

        if !trimmedContent.isEmpty {
            instructionSegments.append("Content:")
            instructionSegments.append(trimmedContent)
        }

        instructionSegments.append(
            "Respond only with XML formatted as <classification><label>VALUE</label></classification>, replacing VALUE with a label from the candidate list. Without explanation or additional text or quotation marks.",
        )
        instructionSegments.append(
            "If you are unsure, use \(primaryCandidate) for VALUE.",
        )

        let message = instructionSegments.joined(separator: "\n\n")

        return Request(
            message: message,
            sanitizedCandidates: sanitizedCandidates,
            primaryCandidate: primaryCandidate,
        )
    }
}

private enum CandidateInputResolver {
    static func resolveCandidates(
        manualCandidates: [String],
    ) throws -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func append(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(normalized).inserted else { return }
            ordered.append(trimmed)
        }

        manualCandidates.forEach(append)

        guard !ordered.isEmpty else {
            throw ShortcutError.invalidCandidates
        }

        return ordered
    }
}

private extension String {
    func extractXMLLabelValue() -> String? {
        guard let labelStart = range(of: "<label>") else {
            return nil
        }

        let searchRange = labelStart.upperBound ..< endIndex
        guard let labelEnd = range(of: "</label>", range: searchRange) else {
            return nil
        }

        let valueRange = labelStart.upperBound ..< labelEnd.lowerBound
        return String(self[valueRange])
    }
}
