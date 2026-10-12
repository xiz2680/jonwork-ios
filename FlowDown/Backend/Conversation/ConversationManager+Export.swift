//
//  ConversationManager+Export.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/30/25.
//

import Foundation
import Storage

extension ConversationManager {
    enum ExportFormat: String, Codable, CaseIterable {
        case plainText
        case markdown
        case json
    }

    func exportConversation(
        identifier: Conversation.ID,
        exportFormat: ExportFormat,
        completion: @escaping (Result<String, Error>) -> Void,
    ) {
        guard let conversation = ConversationManager.shared.conversation(identifier: identifier) else {
            assertionFailure()
            completion(.failure(NSError(domain: "ConversationManager", code: 404, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Unknown Error"),
            ])))
            return
        }
        let session = ConversationSessionManager.shared.session(for: identifier)
        switch exportFormat {
        case .plainText:
            var content: [String] = [String(localized: "Exported Conversation - \(conversation.title)")]
            for message in session.messages {
                let messageText = [
                    message.role.rawValue.capitalized,
                    message.creation.formatted(date: .abbreviated, time: .omitted),
                    message.reasoningContent,
                    message.document,
                ]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                content.append(messageText)
            }
            let markdownContent = content
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            completion(.success(markdownContent))

        case .markdown:
            var content: [String] = [String(localized: "Exported Conversation - \(conversation.title)")]
            for message in session.messages {
                let messageText = [
                    "## \(message.role.rawValue.capitalized) - \(message.creation.formatted(date: .abbreviated, time: .omitted))",
                    message.reasoningContent.isEmpty ? "" : " > \(message.reasoningContent)",
                    message.document,
                ]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                content.append(messageText)
            }
            let markdownContent = content
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n---\n\n")
            completion(.success(markdownContent))

        case .json:
            let exportData: [String: Any] = [
                "metadata": conversation,
                "messages": session.messages,
            ]
            do {
                let propertyListData = try JSONSerialization.data(withJSONObject: exportData, options: [
                    .prettyPrinted,
                    .fragmentsAllowed,
                    .sortedKeys,
                ])
                guard let propertyListString = String(data: propertyListData, encoding: .utf8) else {
                    throw NSError(domain: "ConversationManager", code: 500, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Failed to decode data."),
                    ])
                }
                completion(.success(propertyListString))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
