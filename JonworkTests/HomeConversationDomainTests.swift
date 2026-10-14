@testable import Jonwork
import Foundation
import PDFKit
import Testing

struct HomeConversationDomainTests {
    private let identity = HomeGateway.Identity(subject: "verified-subject", scopeType: .personal, scopeId: "", workspaceId: "personal-workspace", generation: String(repeating: "a", count: 64))

    @Test
    func HomeBranchProjectionPreservesBothBranchesAndStructuredVisualizeUsage() throws {
        let session: PiJSONValue = .object([
            "session_id": .string("unified-fixture"), "title": .string("Actual fixture"), "status": .string("completed"),
            "preferences": .object(["selected_branches": .object(["1": .number(3)])]),
            "messages": .array([
                message(id: 1, parent: nil, role: "user", content: "Original"),
                message(id: 2, parent: 1, role: "assistant", content: "Original preserved"),
                message(id: 3, parent: 1, role: "user", content: "Edited"),
                message(id: 4, parent: 3, role: "assistant", content: "Visual result", capability: "visualize", events: [.object([
                    "type": .string("result"), "metadata": .object([
                        "render_type": .string("mermaid"), "code": .object(["language": .string("mermaid"), "content": .string("graph LR\nA-->B")]),
                        "metadata": .object(["cost_summary": .object(["total_tokens": .number(17), "total_calls": .number(2)])]),
                    ]),
                ])]),
            ]),
        ])
        let projection = try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: identity, session: session), expectedIdentity: identity)
        #expect(projection.allMessages.map(\.id) == [1, 2, 3, 4])
        #expect(projection.visibleMessages.map(\.id) == [1, 3, 4])
        #expect(projection.rawSession == session)
        #expect(projection.visibleMessages.last?.visualizeResult?["code"]?["content"]?.stringValue == "graph LR\nA-->B")
        #expect(projection.visibleMessages.last?.usage?["total_tokens"] == .number(17))
        #expect(projection.visibleMessages.first?.usage == nil)
    }

    @Test
    func researchOutlineConfirmationAndClarificationDoNotBecomeCompletedMessages() throws {
        let outline = message(id: 1, parent: nil, role: "assistant", content: "Plan", capability: "deep_research", events: [.object([
            "type": .string("result"), "metadata": .object(["outline_preview": .bool(true), "sub_topics": .array([.object(["title": .string("Topic"), "overview": .string("Real fixture outline")])])]),
        ])])
        let question = message(id: 2, parent: 1, role: "assistant", content: "Clarify", events: [.object(["type": .string("ask_user"), "metadata": .object(["questions": .array([])])])])
        let session: PiJSONValue = .object(["session_id": .string("home"), "title": .string("Research"), "messages": .array([outline, question])])
        let projection = try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: identity, session: session), expectedIdentity: identity)
        #expect(projection.allMessages[0].phase == .awaitingOutlineConfirmation)
        #expect(projection.allMessages[1].phase == .awaitingClarification)
        #expect(projection.allMessages[0].raw == outline)
    }

    @Test
    func changedHomeIdentityOrGenerationRejectsOldSnapshot() {
        let other = HomeGateway.Identity(subject: "other", scopeType: .personal, scopeId: "", workspaceId: identity.workspaceId, generation: identity.generation)
        let raw: PiJSONValue = .object(["session_id": .string("home"), "title": .string("Private"), "messages": .array([])])
        #expect(throws: PiServiceError.invalidResponse) {
            try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: other, session: raw), expectedIdentity: identity)
        }
    }

    @Test(arguments: ["pi.gateway", " home.read", "home.read ", "home.read pi.gateway"])
    func HomeCredentialScopeNeverAcceptsPiOrWhitespaceFallback(_ scope: String) {
        let tokens = HomeOAuthTokens(accessToken: String(repeating: "a", count: 32), refreshToken: String(repeating: "b", count: 32), expiresAt: .distantFuture, refreshExpiresAt: .distantFuture, scope: scope)
        #expect(throws: PiOAuthError.invalidAuthorizationResponse) { try tokens.validate() }
    }

    @Test
    func persistedRecoverableErrorsDoNotPoisonSuccessfulResultWithoutDone() {
        let result = event("result", ["response": .string("Actual result")])
        #expect(HomeTurnOutcome.phase(events: [event("error", ["trace_kind": .string("subagent_event")]), result]) == .completed)
        #expect(HomeTurnOutcome.phase(events: [result, event("error", ["trace_kind": .string("tool_result")])]) == .completed)
        #expect(HomeTurnOutcome.phase(events: [event("error", ["trace_kind": .string("tool_result")]), event("done", ["status": .string("completed")])]) == .completed)
    }

    @Test
    func terminalFatalOverridesMisleadingResultAndCompletedDone() {
        let fatal = event("error", ["turn_terminal": .bool(true), "status": .string("failed")])
        #expect(HomeTurnOutcome.phase(events: [fatal]) == .failed)
        #expect(HomeTurnOutcome.phase(events: [fatal, event("result"), event("done", ["status": .string("completed")])]) == .failed)
        #expect(HomeTurnOutcome.phase(events: [event("error", ["turn_terminal": .bool(true)])]) == .failed)
        #expect(HomeTurnOutcome.phase(events: [event("error", ["turn_terminal": .bool(true), "status": .string("cancelled")])]) == .cancelled)
        #expect(HomeTurnOutcome.phase(events: [event("done", ["status": .string("aborted")])]) == .cancelled)
        #expect(HomeTurnOutcome.phase(events: [event("progress")]) == .stopped)
    }

    @Test(arguments: ["failed", "rejected", "cancelled", "aborted"])
    func authoritativeFailedSnapshotOverridesSavedResult(_ status: String) throws {
        let session: PiJSONValue = .object(["session_id": .string("home"), "title": .string("Research"), "status": .string(status),
            "messages": .array([message(id: 1, parent: nil, role: "assistant", content: "Saved result", events: [event("result")])])])
        let projection = try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: identity, session: session), expectedIdentity: identity)
        #expect(projection.phase == (["cancelled", "aborted"].contains(status) ? .cancelled : .failed))
    }

    @Test
    func actualAskUserToolMetadataRemainsWaitingUntilMatchingResolution() {
        let question: PiJSONValue = .object(["type": .string("tool_result"), "tool_call_id": .string("question-call"), "metadata": .object([
            "tool_metadata": .object(["ask_user": .object(["questions": .array([.object(["id": .string("topic"), "question": .string("Which topic?")])])])])])])
        #expect(HomeTurnOutcome.phase(events: [question, event("done", ["status": .string("completed")])]) == .awaitingClarification)
        let resolution = event("progress", ["ask_user_resolved": .bool(true), "ask_user_tool_call_id": .string("question-call"), "answers": .array([])])
        #expect(HomeTurnOutcome.phase(events: [question, resolution, event("result")]) == .completed)
        #expect(HomeTurnOutcome.phase(events: [event("result", ["outline_preview": .bool(true)]), event("done", ["status": .string("completed")])]) == .awaitingOutlineConfirmation)
    }

    @Test
    func realRetryTurnIgnoresEarlierFatalButPreservesRawTrace() {
        let old: PiJSONValue = .object(["type": .string("error"), "turn_id": .string("old-turn"), "metadata": .object(["turn_terminal": .bool(true)])])
        let retry: PiJSONValue = .object(["type": .string("result"), "turn_id": .string("retry-turn"), "metadata": .object([:])])
        #expect(HomeTurnOutcome.phase(events: [old, retry]) == .completed)
    }

    @Test
    func publicContractFixturesPreserveSnapshotAndTypedReplayOutcomes() throws {
        func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Home1/home1-" + name + ".json")
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        let snapshot = try fixture("snapshot", as: HomeGateway.Snapshot.self)
        let projection = try HomeConversationProjection(snapshot: snapshot, expectedIdentity: snapshot.identity)
        #expect(projection.rawSession == snapshot.session)
        #expect(projection.allMessages.count >= projection.visibleMessages.count)
        let failed = try fixture("replay-failed-research", as: HomeGateway.Replay.self)
        #expect(HomeTurnOutcome.phase(events: failed.events) == .failed)
        let outline = try fixture("outline-confirmation", as: HomeGateway.Replay.self)
        #expect(HomeTurnOutcome.phase(events: outline.events) == .awaitingOutlineConfirmation)
        let discovery = try fixture("discovery", as: HomeDiscovery.self)
        try discovery.validate(baseURL: discovery.authentication.tokenEndpoint.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        let handshake = try fixture("handshake", as: HomeGateway.Handshake.self)
        try handshake.validateReadOnly()
    }

    @Test(arguments: ["", "Actual plain content"]) @MainActor
    func structuredVisualizeCodeSurvivesFullAndSelectedMarkdownAndPDF(_ content: String) throws {
        let code = "graph LR\nACTUAL_SOURCE_A-->ACTUAL_SOURCE_B"
        let raw = message(id: 2, parent: 1, role: "assistant", content: content, capability: "visualize", events: [event("result", [
            "render_type": .string("mermaid"), "code": .object(["language": .string("mermaid"), "content": .string(code)])])])
        let session: PiJSONValue = .object(["session_id": .string("home"), "title": .string("Graph"), "messages": .array([
            message(id: 1, parent: nil, role: "user", content: "Actual question"), raw])])
        let projection = try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: identity, session: session), expectedIdentity: identity)
        let result = try #require(projection.visibleMessages.last)
        #expect(result.content == content)
        #expect(result.raw == raw)
        #expect(result.usage == nil)
        #expect(result.presentationText.contains("```mermaid\n" + code))
        let picker = PiConversationExportController(title: projection.title, messages: projection.visibleMessages.map(\.exportMessage), authorization: { true })
        picker.loadViewIfNeeded()
        picker.tableView.selectRow(at: IndexPath(row: 1, section: 0), animated: false, scrollPosition: .none)
        let selectedData = try #require(picker.exportData(pdf: false))
        let selectedMarkdown = try #require(String(data: selectedData, encoding: .utf8))
        #expect(selectedMarkdown.contains(code))
        #expect(!selectedMarkdown.contains("Actual question"))
        let selectedPDFData = try #require(picker.exportData(pdf: true))
        let selectedPDF = try #require(PDFDocument(data: selectedPDFData))
        #expect(selectedPDF.page(at: 0)?.string?.contains("ACTUAL_SOURCE_A") == true)
        for selection in [projection.visibleMessages.map(\.exportMessage), [result.exportMessage]] {
            #expect(PiConversationExport.markdown(title: projection.title, messages: selection).contains(code))
            let pdf = try #require(PDFDocument(data: PiConversationExport.pdf(title: projection.title, messages: selection)))
            let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
            #expect(text.contains("ACTUAL_SOURCE_A"))
            #expect(text.contains("ACTUAL_SOURCE_B"))
        }
    }

    @Test
    func typedActivityUsesActualStagesOutlineResultsAndSuppliedUsageOnly() throws {
        let result = event("result", ["render_type": .string("mermaid"), "code": .object(["content": .string("graph LR\nA-->B")]),
            "metadata": .object(["cost_summary": .object(["total_tokens": .number(17)])])])
        let outline = event("result", ["outline_preview": .bool(true), "sub_topics": .array([.object(["title": .string("Actual topic"), "overview": .string("Actual overview")])])])
        let session: PiJSONValue = .object(["session_id": .string("home"), "title": .string("Activity"), "messages": .array([
            message(id: 1, parent: nil, role: "assistant", content: "", events: [event("progress"), outline, result])])])
        let projection = try HomeConversationProjection(snapshot: .init(contract: HomeGateway.contract, identity: identity, session: session), expectedIdentity: identity)
        let activity = HomeConversationActivity(projection: projection)
        #expect(activity.execution.count == 1)
        #expect(activity.execution[0].title == "deep_research · researching")
        #expect(activity.results[0].detail == "graph LR\nA-->B")
        #expect(activity.outlines[0].title == "Actual topic")
        #expect(activity.usage.count == 1)
        #expect(activity.usage[0].title == "total_tokens")
        #expect(activity.usage[0].subtitle == "17")
    }

    private func event(_ type: String, _ metadata: [String: PiJSONValue] = [:]) -> PiJSONValue {
        .object(["type": .string(type), "source": .string("deep_research"), "stage": .string("researching"), "content": .string(""), "timestamp": .number(1), "metadata": .object(metadata)])
    }

    private func message(id: Int, parent: Int?, role: String, content: String, capability: String? = nil, events: [PiJSONValue] = []) -> PiJSONValue {
        .object(["id": .number(Double(id)), "parent_message_id": parent.map { .number(Double($0)) } ?? .null,
                 "role": .string(role), "content": .string(content), "capability": capability.map(PiJSONValue.string) ?? .null, "events": .array(events), "attachments": .array([])])
    }
}
