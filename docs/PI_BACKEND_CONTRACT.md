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

The versioned Jonwork gateway exposes the `pi-gateway/1.0` contract, OAuth 2 authorization-code authentication with PKCE, authoritative snapshots, replayable SSE, idempotent mutations, controller ownership, and capability/limit discovery. UIKit remains independent of the wire format: `PiServiceProtocol` is the replaceable transport boundary, `PiEventAdapter` validates ordered events, `PiSessionReducer` owns deterministic state transitions, and Jonwork views consume presentation models only.

The client must fail closed when a required capability is absent. It must never silently downgrade a requested Pi agent session to stateless chat completions.

## Gateway Endpoints

- `GET /.well-known/pi-gateway`
- `GET /v1/repositories`
- `GET /v1/models`
- `GET` and `POST /v1/sessions`
- `GET` and `PATCH /v1/sessions/{sessionId}`
- `POST /v1/sessions/{sessionId}/restore`
- `GET /v1/sessions/{sessionId}/events`
- `POST /v1/sessions/{sessionId}/commands`
- `POST /v1/sessions/{sessionId}/takeover`
- `POST /v1/sessions/{sessionId}/release`
- `GET /v1/sessions/{sessionId}/mutation-receipt`
- `POST /v1/attachments`

Mutation requests use `Idempotency-Key` and revision fencing. Swift fixtures freeze discovery, snapshot, event, receipt, and error payloads. Deletion uses `DELETE /v1/sessions/{sessionId}` with `{ "clientId": "…" }` and requires an applied receipt with `deleted: true`; search uses the versioned `query`, `state`, and `limit` parameters on the session list.

Discovery is accepted only when API `1.0` falls inside the declared `minimumApiVersion`/`maximumApiVersion` contract and every required capability, including `sessionSearch` and `sessionDelete`, is true. Session lists require `total` and `authoritative: true`. Model attachment metadata is required; missing metadata never implies attachment support.

## Command Mapping

| iOS action | Pi command |
|---|---|
| Send prompt | `prompt` |
| Steer active run | `prompt` with `deliverAs: steer` |
| Queue follow-up | `prompt` with `deliverAs: followUp` |
| Stop current run | `abort` |
| Select model | `set_model` |
| Set reasoning depth | `set_thinking_level` |
| Rename session | `PATCH /v1/sessions/{sessionId}` |
| Become controller | takeover request |
| Return control to CLI | release request |

## Event Mapping

| Pi event | Product presentation |
|---|---|
| authoritative snapshot | Replace history, configuration, role, and controller state |
| `operation.accepted` / `operation.settled` | Track one idempotent operation through completion or retryable failure |
| `user.message` | Upsert the stable user row |
| `turn.started` / `turn.completed` | Track the active run without creating presentation rows |
| `assistant.message.started` / `assistant.message.completed` | Allocate and finalize the stable assistant row |
| `assistant.text.delta` | Incrementally update assistant Markdown source |
| `assistant.reasoning.delta` | Incrementally update the existing reasoning view |
| `tool.started` / `tool.updated` / `tool.completed` | Reuse and update one stable tool card |
| `abort.requested` | Preserve history while the active operation stops |
| `gateway.error` | Present typed failure and retry availability |
| `controller.changed` | Update composer availability and ownership banner |
| `session.released` | Close live mutation controls and return to the server session list |

## Session Safety

- One Pi runtime has at most one controller.
- Viewer mode disables all mutation controls, including abort, and continues live rendering.
- Takeover is unavailable while streaming if the gateway rejects it.
- Abort stops the run and preserves session history.
- Release aborts if necessary, disposes the web runtime, closes the stream, and preserves the JSONL session for native CLI resume.
- Reconnect first obtains authoritative state, then resumes streaming. UI-local message state must never be treated as authoritative history.
- Reconnect replaces state from an authoritative snapshot, then resumes after the snapshot event ID. An expired cursor triggers another authoritative replacement.
- Duplicate events are reduced idempotently by stable message and tool-call identity whenever the gateway supplies one.
- The client does not automatically resend a prompt after an ambiguous network failure.
- A `202` response for `set_model` or `set_thinking_level` is admission only. The selector stays pending until the matching `operation.settled`; after successful settlement, a fresh authoritative snapshot must confirm the requested configuration.

## Security

- Store bearer tokens in Keychain with the narrowest practical accessibility class.
- Never put tokens in URLs, analytics, crash metadata, or logs in production.
- Require TLS for non-local connections and validate the server trust chain.
- Treat message, Markdown, attachment, and tool output as untrusted content.
- Do not execute links, scripts, files, or tool output without explicit product behavior and platform safeguards.
- Enforce upload size, type, and timeout limits at both app and gateway.
- Provide account/session data deletion paths required by the selected distribution model.

## Known Contract Gaps

- Restoring and takeover-pending are client request phases, not durable gateway snapshot fields.
- Attachment support is limited by the intersection of required discovery metadata, discovery media types/limits, and the selected model's required `attachments` metadata and `input` values.

These are release blockers, not client-side fallback opportunities.

## Compatibility

Unsupported API compatibility ranges fail closed with an update action. Required capabilities do not silently degrade core session safety.
