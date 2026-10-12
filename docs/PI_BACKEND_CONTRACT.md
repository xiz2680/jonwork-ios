# Pi Backend Integration Contract

## Boundary

The iOS app connects through a versioned Pi gateway abstraction. Pi owns models, credentials, agent execution, tools, durable session files, and concurrency semantics. The app owns presentation, local connection profiles, Keychain references, and transient UI state.

```text
FlowDown UIKit views
        ↓
Conversation domain models
        ↓
PiEventAdapter
        ↓
PiService (HTTP + SSE)
        ↓
Pi gateway / Pi agent runtime
```

## Backend Reality and Delivery Decision

The repository audit on 2026-10-12 found two incompatible server surfaces:

1. `jonwork-server` contract `1.2.0` provides production iOS PKCE/device authentication, model discovery, and OpenAI-compatible chat SSE. It does not expose Pi session CRUD, authoritative state, controller/viewer ownership, tool lifecycle events, takeover, or release.
2. `pi-mobile` provides the session HTTP/SSE surface below, but uses optional static-token authentication, has no capability/version document, and currently pins `pi-coding-agent ~0.53.0` while `jonwork-pi` is `1.1.0` with protocol version 8.

Therefore the app must not couple UIKit to either wire format. `PiServiceProtocol` is the replaceable boundary, `PiSessionReducer` owns deterministic state transitions, and FlowDown views consume presentation models only. The current implementation targets `pi-mobile` for the agent-session vertical slice. Production distribution remains blocked until a gateway combines Jonwork device authentication with a versioned current-Pi session contract.

The client must fail closed when a required capability is absent. It must never silently downgrade a requested Pi agent session to stateless chat completions.

## Development Gateway Endpoints

The first adapter targets the existing gateway surface:

- `GET /health`
- `GET /api/repos`
- `GET /api/models`
- `GET /api/sessions`
- `GET /api/active-sessions`
- create or resume session endpoint under `/api/sessions`
- session state and SSE event stream
- session command endpoint
- takeover and release endpoints

The concrete paths and payload schemas are checked against `/Users/a/xz-workspace/pi-mobile/src/types.ts` and `/Users/a/xz-workspace/pi-mobile/src/server.ts`. Swift request and response fixtures are versioned with adapter tests.

## Command Mapping

| iOS action | Pi command |
|---|---|
| Send prompt | `prompt` |
| Steer active run | `prompt` with `deliverAs: steer` |
| Queue follow-up | `prompt` with `deliverAs: followUp` |
| Stop current run | `abort` |
| Select model | `set_model` |
| Set reasoning depth | `set_thinking_level` |
| Configure queue behavior | `set_steering_mode`, `set_follow_up_mode` |
| Rename session | `set_session_name` |
| Become controller | takeover request |
| Return control to CLI | release request |

## Event Mapping

| Pi event | Product presentation |
|---|---|
| `init` | Replace session snapshot, role, and controller state |
| `state_patch` | Update model, reasoning, name, usage, and modes |
| `controller_changed` | Update composer availability and ownership banner |
| `released` | Close live stream and show safe CLI-resume state |
| `turn_start` / `agent_start` | Begin active response state |
| `message_start` | Allocate user or assistant row |
| `message_update` text delta | Incrementally update assistant Markdown source |
| `message_update` thinking/reasoning delta | Incrementally update reasoning view |
| `message_end` | Final render, stop reason, and error state |
| `tool_execution_start` | Create pending tool card |
| `tool_execution_update` | Update tool progress without replacing the card |
| `tool_execution_end` | Resolve tool card as success or error |
| `agent_end` | End model activity; retain retry state when applicable |
| `agent_settled` | Mark composer ready and finalize run state |
| retry and compaction events | Show compact non-blocking operational status |

## Session Safety

- One Pi runtime has at most one controller.
- Viewer mode disables all mutation controls, including abort, and continues live rendering. The current development gateway incorrectly permits viewer abort; the client does not expose it and the production gateway must reject it.
- Takeover is unavailable while streaming if the gateway rejects it.
- Abort stops the run and preserves session history.
- Release aborts if necessary, disposes the web runtime, closes the stream, and preserves the JSONL session for native CLI resume.
- Reconnect first obtains authoritative state, then resumes streaming. UI-local message state must never be treated as authoritative history.
- The current gateway does not provide SSE event IDs or replay cursors. Reconnect replaces the entire snapshot and only then consumes new events; no exactly-once claim is made across a disconnected interval.
- Duplicate events are reduced idempotently by stable message and tool-call identity whenever the gateway supplies one.
- The client does not automatically resend a prompt after an ambiguous network failure.

## Security

- Store bearer tokens in Keychain with the narrowest practical accessibility class.
- Never put tokens in URLs, analytics, crash metadata, or logs in production.
- Require TLS for non-local connections and validate the server trust chain.
- Treat message, Markdown, attachment, and tool output as untrusted content.
- Do not execute links, scripts, files, or tool output without explicit product behavior and platform safeguards.
- Enforce upload size, type, and timeout limits at both app and gateway.
- Provide account/session data deletion paths required by the selected distribution model.

## Known Contract Gaps

- The production server has no Pi session service.
- The development gateway has no API version or capability discovery.
- Development SSE has no event ID, replay cursor, or resumable stream.
- Development authentication is not suitable for App Store production and its browser UI permits tokens in query parameters.
- Development prompt commands are text-only; image/file attachment parity is not yet available.
- `agent_settled` and current Pi 1.1 events are not guaranteed by the gateway's pinned 0.53 dependency.

These are release blockers, not client-side fallback opportunities.

## Compatibility

The production gateway must expose an API version and capability document before App Store release. Unsupported major versions fail with a clear upgrade message. Optional capabilities are feature-gated; they do not silently degrade core session safety.
