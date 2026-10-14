# Pi iOS Product Scope

## Approved XIZ-134 Home scope

Linear XIZ-134's top latest execution requirements supersede the historical Pi-only first-release exclusions below. The current product target is the actual authenticated Jonwork Home conversation backed by DeepTutor, including chat/research/visualize, permission-filtered references, images/documents, authoritative message branches and actions, notebook/export/results/clarification/usage, account and identity flows, and native accessibility/draft/pin extensions. Pi Mobile is not the parity baseline. See `conversation-feature-matrix.md` for existing, conditional, native-extension and missing-contract classifications.

Use the approved six-state reference: history, chat, add/reference, activity/results, settings, and settings/model-and-AI. All model/thinking/default/current-session configuration belongs only in settings. Reuse UIKit, existing timeline/Markdown/editor/pickers/previews/settings and preserve native transitions, gestures, keyboard/stream/scroll/stop behavior, haptics and Reduce Motion. A missing safe backend operation remains an explicit blocker; hiding its control does not complete parity.

Independent initial and final native evidence is required. API/fixture success and historical tests do not establish current device acceptance. Physical-device and simulator evidence remain separate. XIZ-134 does not authorize an App Store submission.

## Product Position

Pi iOS is a native control surface for Pi agent sessions. Its product promise is a calm, premium, trustworthy conversation experience for professional work. FlowDown provides the interaction and rendering foundation; Pi remains the only agent backend.

## Experience Principles

1. Conversation is the product. Navigation, settings, and status should support the active task without competing with it.
2. Streaming must feel continuous. Text, reasoning, and tool progress update without layout jumps or scroll loss.
3. Agent state must be visible. Users can always tell whether Pi is thinking, using a tool, waiting, retrying, stopped, disconnected, or complete.
4. Control must be safe. Abort, takeover, release, retry, and destructive actions communicate their effect before execution.
5. Recovery is normal. Reconnect and history restoration preserve context and never create concurrent session writers.
6. Advanced capability stays progressive. Tool details, model controls, usage, and diagnostics appear on demand.

## First Release Journeys

### Connect

- Add a Pi server using HTTPS or an approved local-development endpoint.
- Authenticate without exposing the token after entry.
- Verify server compatibility and show actionable errors.

### Find Work

- Browse repositories and recent sessions.
- Distinguish active, resumable, released, and unavailable sessions.
- Search and rename conversations.

### Converse

- Start or resume a session.
- Send a prompt and receive streaming reasoning, text, and tools.
- Add a steering message or queue a follow-up while Pi is working.
- Attach supported images or files.
- Stop a run without deleting the session.
- Retry or recover after transport and model errors.

### Coordinate

- Show controller and viewer state.
- Take over only when allowed.
- Release the runtime before continuing in the native Pi CLI.

## FlowDown Reuse Map

| Product need | FlowDown asset | Decision |
|---|---|---|
| Conversation timeline | `MessageListView` and row views | Reuse and adapt models |
| Assistant Markdown and code | `AiMessageView`, MarkdownView, Runestone | Reuse |
| Reasoning presentation | `ReasoningContentView` | Reuse and map Pi deltas |
| Tool progress | `ToolHintView` and tool state views | Reuse with Pi tool payload adapter |
| Composer | `InputEditor`, `ControlPanel`, attachment bar | Reuse and simplify |
| Conversation list | `ConversationSelectionView` | Reuse with Pi summaries |
| Search | conversation search controllers | Reuse after Pi indexing decision |
| Attachments | `RichEditorView`, attachment parsing and picker delegates | Reuse supported types |
| Model controls | existing model controls | Adapt to Pi model registry; remove provider editing |
| Web search and FlowDown tools | FlowDown-specific managers | Remove from product surface; Pi tools are authoritative |
| Local MLX model download | local model controllers | Exclude from first release |
| iCloud conversation sync | Jonwork storage/sync | Exclude; Pi session files are authoritative |

## Visual Quality Bar

- Native iOS spacing, typography, haptics, materials, transitions, and gestures.
- No web view for the main conversation experience.
- Stable 60 fps scrolling on long mixed-content conversations on the oldest supported device.
- No visible relayout flash during token streaming or tool updates.
- Full light/dark mode, Dynamic Type, VoiceOver, Reduce Motion, and increased contrast support.
- Empty, loading, offline, error, permission, and recovery states are designed, not generic alerts.
- Brand assets replace all FlowDown proprietary names, icons, and artwork before distribution.

## Product Metrics

- successful connect rate;
- time from launch to usable conversation;
- prompt-to-first-visible-update latency;
- reconnect and history recovery success rate;
- crash-free sessions;
- aborted runs that remain resumable;
- accessibility critical-issue count;
- App Store rejection and production rollback count.
