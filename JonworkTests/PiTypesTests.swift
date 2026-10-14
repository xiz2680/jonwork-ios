@testable import Jonwork
import Foundation
import Testing

@Suite
struct PiTypesTests {
    @Test
    func `init event decodes authoritative session state`() throws {
        let event = try decode(
            """
            {
              "type": "init",
              "state": {
                "sessionId": "session-1",
                "cwd": "/repo",
                "sessionFile": "/repo/.pi/session.jsonl",
                "sessionName": "Industrial enclosure",
                "isStreaming": true,
                "model": {"provider":"openai","id":"gpt-6.1","name":"GPT 6.1"},
                "thinkingLevel": "medium",
                "steeringMode": "all",
                "followUpMode": "one-at-a-time",
                "stats": null,
                "contextUsage": {"tokens":1200,"contextWindow":128000,"percent":0.9375},
                "messages": [{"id":"u1","role":"user","content":"Refine this form."}]
              },
              "yourClientId": "ios-1",
              "controllerClientId": "ios-1",
              "role": "controller"
            }
            """,
        )

        guard case let .initial(state, clientID, controllerID, role) = event else {
            Issue.record("Expected init event")
            return
        }
        #expect(state.sessionId == "session-1")
        #expect(state.followUpMode == .oneAtATime)
        #expect(state.contextUsage?.tokens == 1200)
        #expect(clientID == "ios-1")
        #expect(controllerID == "ios-1")
        #expect(role == .controller)
    }

    @Test
    func `agent event keeps unknown fields without lossy decoding`() throws {
        let event = try decode(
            """
            {"type":"agent_event","event":{"type":"future_event","nested":{"value":42},"items":[true,"x"]}}
            """,
        )
        guard case let .agent(agent) = event else {
            Issue.record("Expected agent event")
            return
        }
        #expect(agent.type == "future_event")
        #expect(agent.payload["nested"] == .object(["value": .number(42)]))
    }

    @Test
    func `unknown envelope event is rejected`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"type":"future_envelope"}"#)
        }
    }

    @Test
    func `server configuration rejects cleartext remote servers`() throws {
        #expect(throws: PiServiceError.insecureTransport) {
            try PiServerConfiguration(baseURL: #require(URL(string: "http://example.com:3000")))
        }
        let local = try PiServerConfiguration(baseURL: #require(URL(string: "http://127.0.0.1:3000")))
        #expect(local.baseURL.host == "127.0.0.1")
    }

    @Test(arguments: [
        "https://user@pi.example.test",
        "https://user:password@pi.example.test",
        "https://pi.example.test?token=secret",
        "https://pi.example.test#session",
    ])
    func `server configuration rejects authority secrets query and fragment`(_ rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(throws: PiServiceError.invalidServerURL) {
            try PiServerConfiguration(baseURL: url)
        }
    }

    private func decode(_ json: String) throws -> PiServerEvent {
        try JSONDecoder().decode(PiServerEvent.self, from: Data(json.utf8))
    }
}
