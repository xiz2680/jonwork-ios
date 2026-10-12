@testable import ChatClientKit
import Foundation

final class ChatServiceSpy: ChatService, @unchecked Sendable {
    let errorCollector = ErrorCollector.new()

    var chatHandler: @Sendable (ChatRequestBody) async throws -> ChatResponse
    var streamHandler: @Sendable (ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk>
    private(set) var receivedBodies: [ChatRequestBody] = []

    init(
        chatHandler: @escaping @Sendable (ChatRequestBody) async throws -> ChatResponse = { _ in
            ChatResponse(reasoning: "", text: "", images: [], tools: [])
        },
        streamHandler: @escaping @Sendable (ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> = { _ in
            AnyAsyncSequence(
                AsyncStream { continuation in
                    continuation.finish()
                },
            )
        },
    ) {
        self.chatHandler = chatHandler
        self.streamHandler = streamHandler
    }

    func chat(body: ChatRequestBody) async throws -> ChatResponse {
        receivedBodies.append(body)
        return try await chatHandler(body)
    }

    func streamingChat(body: ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> {
        receivedBodies.append(body)
        return try await streamHandler(body)
    }
}

func makeResponseStream(
    _ chunks: [ChatResponseChunk],
) -> AsyncThrowingStream<ChatResponseChunk, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}
