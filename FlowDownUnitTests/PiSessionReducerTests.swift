@testable import FlowDown
import Foundation
import Testing

@Suite
struct PiSessionReducerTests {
    @Test
    func `snapshot projects premium timeline content and ownership`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try decode(
            """
            {
              "type":"init",
              "state":{
                "sessionId":"s1","cwd":"/repo","sessionFile":null,"sessionName":"Concept review",
                "isStreaming":false,"model":null,"thinkingLevel":"high","steeringMode":"all","followUpMode":"all",
                "stats":null,"contextUsage":null,
                "messages":[
                  {"id":"u1","role":"user","content":"Review the enclosure."},
                  {"id":"a1","role":"assistant","content":[
                    {"type":"thinking","thinking":"Checking constraints"},
                    {"type":"text","text":"The radius needs revision."}
                  ]}
                ]
              },
              "yourClientId":"ios","controllerClientId":"ios","role":"controller"
            }
            """,
        ))

        #expect(reducer.state.title == "Concept review")
        #expect(reducer.state.role == .controller)
        #expect(reducer.state.messages.map(\.id) == ["u1", "a1"])
        #expect(reducer.state.messages[1].reasoning == "Checking constraints")
        #expect(reducer.state.messages[1].text == "The radius needs revision.")
    }

    @Test
    func `authoritative assistant updates replace rather than duplicate`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try emptyInitial())
        reducer.reduce(try decode(
            #"{"type":"agent_event","event":{"type":"agent_start"}}"#,
        ))
        let first = try decode(
            #"{"type":"agent_event","event":{"type":"message_update","message":{"id":"a1","role":"assistant","content":[{"type":"text","text":"Hello"}]}}}"#,
        )
        reducer.reduce(first)
        reducer.reduce(first)
        reducer.reduce(try decode(
            #"{"type":"agent_event","event":{"type":"message_update","message":{"id":"a1","role":"assistant","content":[{"type":"text","text":"Hello world"}]}}}"#,
        ))

        #expect(reducer.state.messages.count == 1)
        #expect(reducer.state.messages[0].text == "Hello world")
    }

    @Test
    func `messages without gateway identifiers keep one stable live row`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try emptyInitial())
        reducer.reduce(try decode(#"{"type":"agent_event","event":{"type":"message_start","message":{"role":"assistant","content":[{"type":"text","text":"Hel"}]}}}"#))
        reducer.reduce(try decode(#"{"type":"agent_event","event":{"type":"message_update","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}}"#))
        let end = try decode(#"{"type":"agent_event","event":{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}}"#)
        reducer.reduce(end)
        reducer.reduce(end)

        #expect(reducer.state.messages.count == 1)
        #expect(reducer.state.messages[0].id == "live-message-0")
        #expect(reducer.state.messages[0].text == "Hello")
    }

    @Test
    func `tool lifecycle preserves stable row identity`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try emptyInitial())
        reducer.reduce(try decode(
            #"{"type":"agent_event","event":{"type":"tool_execution_start","toolCallId":"call-1","toolName":"shell","args":{"cmd":"pwd"}}}"#,
        ))
        reducer.reduce(try decode(
            #"{"type":"agent_event","event":{"type":"tool_execution_update","toolCallId":"call-1","toolName":"shell","partialResult":"/repo"}}"#,
        ))
        reducer.reduce(try decode(
            #"{"type":"agent_event","event":{"type":"tool_execution_end","toolCallId":"call-1","toolName":"shell","result":"done","isError":false}}"#,
        ))

        #expect(reducer.state.messages.count == 1)
        #expect(reducer.state.messages[0].id == "tool-call-1")
        #expect(reducer.state.messages[0].tool?.state == .succeeded)
        #expect(reducer.state.messages[0].tool?.detail == "done")
    }

    @Test
    func `authoritative snapshot projects tool calls and results into one tool row`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try decode(
            """
            {
              "type":"init",
              "state":{
                "sessionId":"s1","cwd":"/repo","sessionFile":null,"isStreaming":false,
                "model":null,"thinkingLevel":"off","steeringMode":"all","followUpMode":"all",
                "stats":null,"contextUsage":null,
                "messages":[
                  {"role":"assistant","content":[{"type":"toolCall","id":"call-1","name":"shell","arguments":{"cmd":"pwd"}}]},
                  {"role":"toolResult","toolCallId":"call-1","toolName":"shell","content":"/repo","isError":false}
                ]
              },
              "yourClientId":"ios","controllerClientId":"ios","role":"controller"
            }
            """
        ))

        #expect(reducer.state.messages.count == 1)
        #expect(reducer.state.messages[0].id == "tool-call-1")
        #expect(reducer.state.messages[0].role == .tool)
        #expect(reducer.state.messages[0].tool?.state == .succeeded)
        #expect(reducer.state.messages[0].tool?.detail == "/repo")
    }

    @Test
    func `nullable state patch clears authoritative optional values`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try decode(
            """
            {"type":"init","state":{"sessionId":"s1","cwd":"/repo","sessionFile":null,"isStreaming":false,
            "model":{"provider":"openai","id":"model","name":"Model"},"thinkingLevel":"off",
            "steeringMode":"all","followUpMode":"all","stats":null,
            "contextUsage":{"tokens":10,"contextWindow":100,"percent":10},"messages":[]},
            "yourClientId":"ios","controllerClientId":"ios","role":"controller"}
            """
        ))
        reducer.reduce(try decode(#"{"type":"state_patch","patch":{"model":null,"contextUsage":null}}"#))

        #expect(reducer.state.model == nil)
        #expect(reducer.state.contextUsage == nil)
    }

    @Test
    func `controller and release transitions disable mutation`() throws {
        var reducer = PiSessionReducer()
        reducer.reduce(try emptyInitial(role: "controller", controller: "ios"))
        reducer.reduce(try decode(#"{"type":"controller_changed","controllerClientId":"other"}"#))
        #expect(reducer.state.role == .viewer)
        reducer.reduce(try decode(#"{"type":"released","byClientId":"other"}"#))
        #expect(reducer.state.isReleased)
        #expect(!reducer.state.isStreaming)
    }

    private func emptyInitial(role: String = "viewer", controller: String? = nil) throws -> PiServerEvent {
        let controllerJSON = controller.map { "\"\($0)\"" } ?? "null"
        return try decode(
            """
            {"type":"init","state":{"sessionId":"s1","cwd":"/repo","sessionFile":null,"isStreaming":false,
            "model":null,"thinkingLevel":"off","steeringMode":"all","followUpMode":"all","stats":null,
            "contextUsage":null,"messages":[]},"yourClientId":"ios","controllerClientId":\(controllerJSON),"role":"\(role)"}
            """,
        )
    }

    private func decode(_ json: String) throws -> PiServerEvent {
        try JSONDecoder().decode(PiServerEvent.self, from: Data(json.utf8))
    }
}
