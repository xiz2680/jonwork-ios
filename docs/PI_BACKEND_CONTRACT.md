# Pi Backend Integration Contract

## Boundary

The iOS app connects to a Pi gateway compatible with the existing `pi-mobile` HTTP and SSE contract. Pi owns models, credentials, agent execution, tools, durable session files, and concurrency semantics. The app owns presentation, local connection profiles, and transient UI state.

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

## Initial Endpoints

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

The concrete paths and payload schemas are generated from or checked against `/Users/a/xz-workspace/pi-mobile/src/types.ts` and `/Users/a/xz-workspace/pi-mobile/src/server.ts`. Swift request and response fixtures must be versioned with the adapter tests.

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
- Viewer mode disables mutation controls but continues live rendering.
- Takeover is unavailable while streaming if the gateway rejects it.
- Abort stops the run and preserves session history.
- Release aborts if necessary, disposes the web runtime, closes the stream, and preserves the JSONL session for native CLI resume.
- Reconnect first obtains authoritative state, then resumes streaming. UI-local message state must never be treated as authoritative history.
- Duplicate SSE events are idempotent by session, message, and tool-call identity.
- The client does not automatically resend a prompt after an ambiguous network failure.

## Security

- Store bearer tokens in Keychain with the narrowest practical accessibility class.
- Never put tokens in URLs, analytics, crash metadata, or logs in production.
- Require TLS for non-local connections and validate the server trust chain.
- Treat message, Markdown, attachment, and tool output as untrusted content.
- Do not execute links, scripts, files, or tool output without explicit product behavior and platform safeguards.
- Enforce upload size, type, and timeout limits at both app and gateway.
- Provide account/session data deletion paths required by the selected distribution model.

## Compatibility

The gateway exposes an API version or capability document before App Store release. Unsupported major versions fail with a clear upgrade message. Optional capabilities are feature-gated; they do not silently degrade core session safety.
