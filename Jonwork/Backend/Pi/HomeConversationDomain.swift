import Foundation

/// Home1 is a distinct namespace. These IDs are never Pi session identifiers.
enum HomeGateway {
    static let contract = "jonwork-home/1.0"

    struct Identity: Codable, Equatable, Sendable {
        enum ScopeType: String, Codable, Sendable { case personal, enterprise }
        let subject: String
        let scopeType: ScopeType
        let scopeId: String
        let workspaceId: String
        let generation: String

        func validate() throws {
            guard !subject.isEmpty, !workspaceId.isEmpty, !generation.isEmpty,
                  (scopeType == .personal ? scopeId.isEmpty : !scopeId.isEmpty) else { throw PiServiceError.invalidResponse }
        }
    }

    struct Handshake: Decodable, Equatable, Sendable {
        struct Capabilities: Decodable, Equatable, Sendable {
            let history: Bool
            let snapshot: Bool
            let eventReplay: Bool
            let mutations: Bool
            let identitySwitch: Bool
        }
        struct Blocked: Decodable, Equatable, Sendable { let capability: String; let reason: String }
        let contract: String
        let identity: Identity
        let capabilities: Capabilities
        let blocked: [Blocked]

        func validateReadOnly() throws {
            guard contract == HomeGateway.contract, capabilities.history, capabilities.snapshot,
                  !capabilities.mutations, !capabilities.identitySwitch else { throw PiServiceError.invalidResponse }
            try identity.validate()
        }
    }

    struct History: Decodable, Sendable {
        let contract: String
        let identity: Identity
        let sessions: [PiJSONValue]
    }

    struct Snapshot: Decodable, Sendable {
        let contract: String
        let identity: Identity
        /// Preserve every original field, including branch preferences, artifacts,
        /// request snapshots, nested result metadata and unknown future read fields.
        let session: PiJSONValue
    }

    struct Replay: Decodable, Sendable {
        let contract: String
        let identity: Identity
        let events: [PiJSONValue]
    }
}

struct HomeConversationProjection: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, running, awaitingOutlineConfirmation, awaitingClarification, completed, failed, cancelled, stopped
    }
    struct Message: Equatable, Sendable, Identifiable {
        let id: Int64
        let parentID: Int64?
        let role: String
        let content: String
        let capability: String?
        let events: [PiJSONValue]
        let attachments: [PiJSONValue]
        let raw: PiJSONValue

        var phase: Phase { HomeTurnOutcome.phase(events: events) }

        var visualizeResult: PiJSONValue? {
            events.last { event in
                guard event["type"]?.stringValue == "result", let render = event["metadata"]?["render_type"]?.stringValue else { return false }
                return ["svg", "chartjs", "mermaid", "html", "manim_video", "manim_image"].contains(render)
            }?["metadata"]
        }

        var presentationText: String {
            guard let result = visualizeResult, let code = result["code"]?["content"]?.stringValue else { return content }
            let language = result["code"]?["language"]?.stringValue ?? ""
            // A longer fence preserves code containing its own Markdown fences.
            let longestRun = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, longestRun + 1))
            let block = "\(fence)\(language)\n\(code)\n\(fence)"
            return content.isEmpty ? block : content + "\n\n" + block
        }

        var exportMessage: PiPresentationMessage {
            .init(id: String(id), role: role == "user" ? .user : role == "assistant" ? .assistant : .system,
                  text: presentationText, reasoning: "", tool: nil)
        }

        var usage: PiJSONValue? {
            events.last { $0["type"]?.stringValue == "result" }?["metadata"]?["metadata"]?["cost_summary"]
        }
    }

    let identity: HomeGateway.Identity
    let sessionID: String
    let title: String
    let status: String?
    let allMessages: [Message]
    let visibleMessages: [Message]
    let rawSession: PiJSONValue

    var phase: Phase {
        // Snapshot terminal failure is authoritative even if a result was saved.
        if ["failed", "rejected"].contains(status) { return .failed }
        if ["cancelled", "aborted"].contains(status) { return .cancelled }
        let outcome = HomeTurnOutcome.phase(events: visibleMessages.last?.events ?? [], streaming: status == "running" || status == "queued")
        if outcome != .idle { return outcome }
        if status == "stopped" { return .stopped }
        if status == "completed" { return .completed }
        return .idle
    }

    init(snapshot: HomeGateway.Snapshot, expectedIdentity: HomeGateway.Identity) throws {
        guard snapshot.contract == HomeGateway.contract, snapshot.identity == expectedIdentity,
              let sessionID = snapshot.session["session_id"]?.stringValue, !sessionID.isEmpty,
              let title = snapshot.session["title"]?.stringValue,
              let rows = snapshot.session["messages"]?.arrayValue else { throw PiServiceError.invalidResponse }
        try snapshot.identity.validate()
        var messages: [Message] = []
        var identities: Set<Int64> = []
        for row in rows {
            guard let id = Self.integer(row["id"]), id > 0, identities.insert(id).inserted,
                  let role = row["role"]?.stringValue, ["user", "assistant", "system"].contains(role),
                  let content = row["content"]?.stringValue else { throw PiServiceError.invalidResponse }
            let parent = Self.integer(row["parent_message_id"])
            if row["parent_message_id"] != nil, row["parent_message_id"] != .null, parent == nil { throw PiServiceError.invalidResponse }
            messages.append(.init(id: id, parentID: parent, role: role, content: content, capability: row["capability"]?.stringValue,
                                  events: row["events"]?.arrayValue ?? [], attachments: row["attachments"]?.arrayValue ?? [], raw: row))
        }
        let choices = snapshot.session["preferences"]?["selected_branches"]?.objectValue ?? [:]
        var children: [String: [Message]] = [:]
        for message in messages { children[message.parentID.map(String.init) ?? "null", default: []].append(message) }
        for key in children.keys { children[key]?.sort { $0.id < $1.id } }
        var visible: [Message] = []
        var visited: Set<Int64> = []
        var parent = "null"
        while let siblings = children[parent], let latest = siblings.last {
            let chosen = siblings.first { $0.id == Self.integer(choices[parent]) } ?? latest
            guard visited.insert(chosen.id).inserted else { throw PiServiceError.invalidResponse }
            visible.append(chosen)
            parent = String(chosen.id)
        }
        identity = snapshot.identity
        self.sessionID = sessionID
        self.title = title
        status = snapshot.session["status"]?.stringValue
        allMessages = messages
        visibleMessages = visible
        rawSession = snapshot.session
    }

    private static func integer(_ value: PiJSONValue?) -> Int64? {
        guard case let .number(number) = value, number.isFinite, number.rounded() == number,
              abs(number) <= 9_007_199_254_740_991 else { return nil }
        return Int64(number)
    }
}

extension PiJSONValue {
    subscript(_ key: String) -> PiJSONValue? { objectValue?[key] }
}

/// Typed terminal semantics for preserved live and persisted Home events.
/// A retry's real turn ID fences earlier attempts without deleting their trace.
enum HomeTurnOutcome {
    static func phase(events: [PiJSONValue], streaming: Bool = false) -> HomeConversationProjection.Phase {
        let latestTurn = events.reversed().compactMap { $0["turn_id"]?.stringValue }.first
        let current = events.filter { latestTurn == nil || $0["turn_id"] == nil || $0["turn_id"]?.stringValue == latestTurn }
        let fatal = current.filter { $0["type"]?.stringValue == "error" && $0["metadata"]?["turn_terminal"] == .bool(true) }
        let done = current.filter { $0["type"]?.stringValue == "done" }
        if fatal.contains(where: { !["cancelled", "aborted"].contains($0["metadata"]?["status"]?.stringValue ?? "") }) || done.contains(where: { $0["metadata"]?["status"]?.stringValue == "failed" }) { return .failed }
        if !fatal.isEmpty || done.contains(where: { ["cancelled", "aborted"].contains($0["metadata"]?["status"]?.stringValue ?? "") }) { return .cancelled }
        if streaming { return .running }
        let successfulResult = current.contains { $0["type"]?.stringValue == "result" && $0["metadata"]?["outline_preview"] != .bool(true) }
        if !successfulResult && current.contains(where: { $0["type"]?.stringValue == "result" && $0["metadata"]?["outline_preview"] == .bool(true) }) { return .awaitingOutlineConfirmation }
        var pendingQuestion: String?
        var hasQuestion = false
        for event in current {
            let metadata = event["metadata"]
            if event["type"]?.stringValue == "tool_result", metadata?["tool_metadata"]?["ask_user"]?.objectValue != nil {
                hasQuestion = true
                pendingQuestion = event["tool_call_id"]?.stringValue ?? metadata?["tool_call_id"]?.stringValue
            } else if event["type"]?.stringValue == "ask_user" || (event["type"]?.stringValue == "tool_call" && metadata?["tool"]?.stringValue == "ask_user") {
                hasQuestion = true
                pendingQuestion = event["tool_call_id"]?.stringValue ?? metadata?["tool_call_id"]?.stringValue
            } else if event["type"]?.stringValue == "progress", metadata?["ask_user_resolved"] == .bool(true), pendingQuestion == nil || metadata?["ask_user_tool_call_id"]?.stringValue == pendingQuestion {
                hasQuestion = false
            }
        }
        if hasQuestion { return .awaitingClarification }
        if successfulResult || done.contains(where: { $0["metadata"]?["status"]?.stringValue == "completed" }) { return .completed }
        return current.isEmpty ? .idle : .stopped
    }
}

struct HomeConversationActivity: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case progress, error, result, outline, usage }
        let kind: Kind
        let title: String
        let subtitle: String
        let detail: String
        let visualization: HomeVisualization?

        init(kind: Kind, title: String, subtitle: String, detail: String, visualization: HomeVisualization? = nil) {
            self.kind = kind; self.title = title; self.subtitle = subtitle; self.detail = detail
            self.visualization = visualization
        }
    }
    let phase: HomeConversationProjection.Phase
    let execution: [Row]
    let results: [Row]
    let outlines: [Row]
    let usage: [Row]

    init(projection: HomeConversationProjection) {
        phase = projection.phase
        var execution: [Row] = []
        var results: [Row] = []
        var outlines: [Row] = []
        var usage: [Row] = []
        for message in projection.visibleMessages {
            for event in message.events {
                guard let type = event["type"]?.stringValue else { continue }
                let metadata = event["metadata"]
                let source = event["source"]?.stringValue ?? ""
                let stage = event["stage"]?.stringValue ?? ""
                let content = event["content"]?.stringValue ?? ""
                let detail = Self.jsonText(event)
                if type == "result" {
                    if metadata?["outline_preview"] == .bool(true) {
                        for topic in metadata?["sub_topics"]?.arrayValue ?? [] {
                            guard let title = topic["title"]?.stringValue else { continue }
                            outlines.append(.init(kind: .outline, title: title, subtitle: topic["overview"]?.stringValue ?? "", detail: Self.jsonText(topic)))
                        }
                    } else {
                        let code = metadata?["code"]?["content"]?.stringValue
                        results.append(.init(kind: .result, title: metadata?["render_type"]?.stringValue ?? type,
                                             subtitle: content, detail: code ?? detail, visualization: HomeVisualization(metadata: metadata)))
                    }
                    if let values = metadata?["metadata"]?["cost_summary"]?.objectValue {
                        for key in values.keys.sorted() {
                            guard let value = values[key] else { continue }
                            // Original server keys and supplied values; no inferred units.
                            usage.append(.init(kind: .usage, title: key, subtitle: Self.jsonText(value), detail: Self.jsonText(value)))
                        }
                    }
                } else {
                    execution.append(.init(kind: type == "error" ? .error : .progress, title: [source, stage].filter { !$0.isEmpty }.joined(separator: " · "),
                                           subtitle: content.isEmpty ? type : content, detail: detail))
                }
            }
        }
        self.execution = execution; self.results = results; self.outlines = outlines; self.usage = usage
    }

    static func jsonText(_ value: PiJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
