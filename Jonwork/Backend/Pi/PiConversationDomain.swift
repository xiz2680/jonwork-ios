import Foundation

enum PiConversationAction: Codable, Equatable, Sendable {
    enum Delivery: Codable, Equatable, Sendable { case prompt, steer, followUp }
    case send(text: String, attachmentIDs: [String], delivery: Delivery)
    case abort
    case retry(operationID: String)
    case setModel(provider: String, modelID: String)
    case setThinkingLevel(PiGatewayWire.ThinkingLevel)
    case compact(instructions: String?)
    case rename(String)
    case takeOver
    case release
}

enum PiConversationEvent: Equatable, Sendable {
    struct Tool: Equatable, Sendable {
        let operationID: String
        let turnID: String
        let messageID: String
        let callID: String
        let parentCallID: String?
        let name: String?
        let detail: String?
        let updateSequence: Int?
        let succeeded: Bool?
    }

    case snapshot(PiGatewayWire.Snapshot, clientID: String)
    case operationAccepted(id: String, command: String, retryOf: String?)
    case userMessage(id: String, text: String, attachmentIDs: [String])
    case turnStarted(operationID: String, turnID: String)
    case assistantStarted(operationID: String, turnID: String, messageID: String)
    case assistantTextDelta(messageID: String, delta: String)
    case assistantReasoningDelta(messageID: String, delta: String)
    case toolStarted(Tool)
    case toolUpdated(Tool)
    case toolCompleted(Tool)
    case assistantCompleted(messageID: String, status: String, error: PiConversationFailure?)
    case turnCompleted(operationID: String, turnID: String, status: String)
    case abortRequested(operationID: String, clientID: String)
    case operationSettled(id: String, status: String, retryOf: String?, error: PiConversationFailure?)
    case error(operationID: String?, failure: PiConversationFailure)
    case controllerChanged(previous: String?, current: String?, reason: String)
    case released(byClientID: String)
}

struct PiConversationFailure: Equatable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
}

struct PiMutationContext: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let revision: Int
}

struct PiUploadedAttachment: Equatable, Sendable {
    let attachmentID: String
    let fileName: String
    let mediaType: String
}

enum PiAttachmentError: Error, LocalizedError, Equatable {
    case limitExceeded

    var errorDescription: String? { String(localized: "The selected attachment is too large.") }
}

struct PiAttachmentUpload: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case image, file }
    let data: Data?
    let fileURL: URL?
    let fileName: String
    let mediaType: String
    let kind: Kind

    init(data: Data, fileName: String, mediaType: String, kind: Kind) {
        self.data = data
        fileURL = nil
        self.fileName = fileName
        self.mediaType = mediaType
        self.kind = kind
    }

    init(fileURL: URL, fileName: String, mediaType: String, kind: Kind) {
        data = nil
        self.fileURL = fileURL
        self.fileName = fileName
        self.mediaType = mediaType
        self.kind = kind
    }

    func byteCount() throws -> Int {
        if let data { return data.count }
        guard let fileURL else { throw PiServiceError.invalidResponse }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else {
            throw PiServiceError.invalidResponse
        }
        return size
    }

    func load(maximumBytes: Int) async throws -> Data {
        if let data {
            guard data.count <= maximumBytes else { throw PiAttachmentError.limitExceeded }
            return data
        }
        guard let fileURL else { throw PiServiceError.invalidResponse }
        let size = try byteCount()
        guard size <= maximumBytes else { throw PiAttachmentError.limitExceeded }
        return try await Task.detached(priority: .userInitiated) {
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe, .uncached])
            guard data.count == size, data.count <= maximumBytes else {
                throw PiAttachmentError.limitExceeded
            }
            return data
        }.value
    }
}
