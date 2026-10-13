# Jonwork iOS Conversation Experience Specification

## Product Intent

Jonwork iOS is a calm, professional control surface for Jonwork conversations, not a generic chatbot or a mobile copy of the web application. The active conversation is visually dominant. Navigation, ownership, model controls, usage, and recovery remain available without competing with the work.

The visual baseline is the existing FlowDown UIKit interface: native typography, generous spacing, translucent materials, stable Markdown layout, folded reasoning, compact tool cards, and a grounded composer. Existing FlowDown components are reused before new UI is introduced, while Pi transport and protocol terms remain behind product-level models.

The Jonwork web home is an experience reference, not an iOS wire-contract reference. The iOS application must consume a versioned Jonwork gateway contract and fail closed when required conversation or ownership capabilities are absent.

## Product Vocabulary

User-facing copy uses product language consistently:

| Internal or technical term | User-facing term |
|---|---|
| Pi, Pi Server | Jonwork |
| session | conversation |
| repository, cwd | workspace, project, or the project's display name |
| access token | sign-in credential, only when the user must act on it |
| controller | editing on this device |
| viewer | read-only |
| takeover | edit on this device |
| release runtime, CLI | continue on desktop |
| gateway version | service update, with version details disclosed only when actionable |

Raw server URLs, tokens, provider names, protocol versions, runtime identifiers, tool commands, filesystem paths, event names, and stack traces are hidden from the normal conversation experience. They may appear only in a deliberate enterprise or diagnostic surface when required for setup or support.

## Jonwork Web Capability Disposition

### Must Ship on iOS

- load the conversation surface and recover from an initial connection failure;
- create, browse, resume, switch, rename, search, and delete conversations;
- render authoritative user and assistant history;
- stream text, reasoning, activity, and tool progress without scroll loss or layout jumps;
- send a prompt, steer an active response, queue a follow-up, stop, and retry;
- attach every image and file type accepted by the Jonwork gateway;
- copy message content and open safe links and owned attachments;
- select a Jonwork model and supported thinking level and inspect context usage;
- preserve an unsent draft locally without treating it as conversation history;
- show offline, recovery, ownership, release, and compatibility states;
- prevent duplicate mutations when the outcome of a network request is unknown.

### Reuse from FlowDown

Reuse these components and their established interaction behavior:

- `MessageListView` and existing row views for the conversation timeline;
- `AiMessageView`, MarkdownView, and Runestone for assistant Markdown and code;
- `ReasoningContentView` for subordinate, foldable reasoning;
- `ToolHintView` and tool state views for stable tool progress cards;
- `RichEditorView`, `InputEditor`, and the attachment bar for composition;
- `ConversationSelectionView` for list presentation;
- conversation search controllers for search presentation after an authoritative Jonwork index exists;
- native attachment pickers, parsing, preview delegates, and safe share/open behavior.

### Adapt for Jonwork

- Map authoritative Jonwork message and tool identifiers into FlowDown presentation models. A row must keep one identity from start through completion.
- Back the conversation list, search, rename, delete, and resume actions with authoritative Jonwork data rather than local transient rows.
- Replace legacy model/provider controls with a capability-gated Jonwork model, thinking-level, and context-usage surface.
- Simplify the composer for Jonwork while keeping attachment picking, draft preservation, Dynamic Type, and hardware-keyboard behavior.
- Translate tool names and protocol payloads into concise user outcomes. Raw commands, paths, arguments, and JSON remain progressively disclosed diagnostics, not primary labels.
- Translate browser navigation, downloads, and dialogs into native navigation, share sheets, previews, menus, and confirmation sheets.
- Replace ambiguous global alerts with inline, state-specific recovery wherever the conversation remains visible.

### Web-Only

- `?session=` query parameters and browser history navigation;
- DOM focus traps, responsive sidebar scrims, browser new-tab behavior, and Blob downloads;
- web-specific keyboard hints and shortcuts;
- browser attachment links and browser-specific export mechanics;
- responsive web drawer behavior.

Equivalent user outcomes may be implemented with native iOS conventions, but their web mechanics must not be copied.

### Administration-Only

- raw service URL and static-token entry outside an explicitly authorized connection setup flow;
- provider endpoints, provider credentials, runtime build details, protocol diagnostics, and tool allowlists;
- storage keys, data migration, provenance, quota administration, and sandbox configuration;
- agent-preset administration until a user-facing runtime and product requirement exist;
- server or model configuration needed to make an unavailable deployment operational.

The normal user surface states what the user can do next: reconnect, sign in, update the service, or contact an administrator.

### Remove from the iOS Product Surface

- generic FlowDown multi-provider setup and provider editing;
- local MLX model download and management;
- FlowDown web-search controls, FlowDown tool toggles, and MCP administration;
- FlowDown iCloud conversation sync;
- FlowDown branding, subscriptions, artwork, welcome copy, and cloud-service entry points;
- local-only duplicate, favorite, rename, delete, or search actions for Jonwork conversations when they do not update authoritative Jonwork state.

## Native Information Architecture

### iPhone

- The root is a native conversation list inside a `UINavigationController`.
- Selecting or creating a conversation pushes the conversation detail screen.
- The system back button and interactive back gesture return to the conversation list.
- A visible navigation action also opens the conversation list; no task depends on a hidden edge gesture.
- Released conversations provide a visible **Back to Conversations** action that pops to the list.
- Settings and secondary controls are presented with native sheets, menus, or pushed detail controllers according to platform convention.

### iPad and Mac Catalyst

- Use a native split-view hierarchy with the conversation list in the primary column and conversation detail in the secondary column.
- Selection, restoration, and released-state navigation remain consistent with iPhone semantics.
- Window size changes must not create a second, conflicting navigation model.

### Information Hierarchy

1. Conversation list: recent conversations, search, new conversation, and user-visible availability.
2. Conversation detail: title, ownership/connection status, authoritative timeline, and composer.
3. Progressive controls: model, thinking level, context usage, tool details, and conversation actions.
4. Settings: account and connection, appearance, privacy, help, and about.
5. Enterprise diagnostics: raw endpoints, versions, and support details, hidden from the default journey.

## State Model

The UI state is composed rather than represented by one mutually exclusive enum:

- content: `loading`, `empty`, or `ready`;
- connection: `online`, `offline`, `recovering`, or `versionBlocked`;
- ownership: `controller`, `viewer`, `takeoverPending`, or `released`;
- run: `idle`, `streaming`, or `stopping`;
- failure: `none`, `retryable(operation, requestID)`, or `terminal`.

When more than one condition applies, the presentation priority is:

1. version blocked;
2. released;
3. initial loading;
4. offline or recovering;
5. error or retry;
6. viewer or takeover pending;
7. streaming;
8. empty or idle.

## Conversation State Matrix

| State | Entry condition | Header and timeline | Composer | Primary action and exit |
|---|---|---|---|---|
| Loading | The first authoritative snapshot has not returned. | Title placeholder and progress; stable skeleton rows; local data is not presented as current server state. | Disabled. | No primary action. Exit to error, empty, idle, viewer, released, or version blocked. |
| Empty | The app is online and the authoritative conversation has no messages. | Workspace and current model context with focused first-task guidance. | Ready for text and supported attachments. | Send the first prompt. |
| Idle | The device is controller, online, and no run is active. | Authoritative history, title, ready status, and optional model/context summary. | Ready. | Send. |
| Streaming | The device is controller and an active run is producing or awaiting output. | Stable incremental text, reasoning, activity, and tool updates; a visible stop affordance; preserve scroll unless already pinned to the bottom. | Ready to compose; sending requires an explicit **Steer** or **Follow Up** choice. | Steer, queue, or stop. Exit only on authoritative activity or error state. |
| Offline | The connection is unavailable after at least one authoritative snapshot. | Offline label and last successful sync; retain the last authoritative snapshot without presenting it as live. | Disabled. | Reconnect. |
| Recovering | Reconnect is in progress and a prior snapshot exists. | Reconnecting progress; keep the prior snapshot stable until it is atomically replaced by a new authoritative snapshot. | Disabled. | Cancel reconnect. Never automatically resend an ambiguously delivered prompt. |
| Error | A typed operation or conversation failure is known. | Preserve safe content; show a concise user-facing cause and request ID only when useful for support. | Enabled only when the failed operation does not make mutation unsafe. | Dismiss, reconnect, change a supported setting, or enter retry. |
| Retry | A specific failed operation is known to be safe to repeat. | Keep the failed item in context and label the exact retry target. | Preserve the draft and attachments when submission was not accepted. | Use an explicit action such as **Retry Sending**, **Retry Response**, or **Reconnect**. Return to the preceding stable state on success. |
| Viewer | Another client owns mutation control or this client has not acquired it. | Read-only label and current controller context; continue live timeline rendering. | Read-only; send, stop, model changes, and release are unavailable. | Edit on this device when takeover is allowed. |
| Takeover | A takeover request is pending. | Keep the viewer timeline live; show pending ownership without implying success. | Disabled and protected from duplicate requests. | Cancel when supported. Success enters idle controller; failure returns to viewer with an inline explanation. Takeover is disabled during streaming and explains why. |
| Released | The mobile runtime has been released while durable history remains available on desktop. | Final authoritative snapshot and **Available on desktop** status. | Disabled permanently for this binding. | Back to Conversations. |
| Version blocked | Required service version or capability is absent or incompatible. | Show required and actual compatibility information without loading a partial conversation. | Disabled. | Update the service or contact an administrator. Never downgrade to stateless chat. |

## Interaction Rules

- Text submission receives immediate acknowledgement; the editor does not remain locked for an entire agent run.
- While streaming, the user explicitly selects **Steer** or **Follow Up**. The app never guesses delivery semantics.
- Stop is visible only to the controller. It stops the run without deleting session history.
- Takeover is disabled while streaming and explains why.
- Release confirms that editing moves off this device while the durable conversation remains available on desktop.
- Reconnect obtains and atomically applies the authoritative snapshot before consuming new live events.
- An ambiguously delivered mutation is resolved through an idempotency receipt or surfaced for manual recovery; it is never silently repeated.
- Tool cards retain one stable identity from start through completion. Details are disclosed progressively.
- Reasoning is visually subordinate to the answer, folded by default after completion, and announced appropriately by VoiceOver.
- Destructive conversation deletion requires confirmation and cannot be represented as successful until the authoritative service confirms it.
- Search and rename never claim success from local presentation metadata alone.

## Visual and Accessibility System

- Use system semantic colors and materials; do not hard-code a light-mode palette.
- Use Dynamic Type text styles and content-size-aware spacing.
- Maintain a minimum 44-point interactive target.
- Use SF Symbols by semantic name and pair status color with text and icon shape.
- Respect Reduce Motion by replacing spring and scale transitions with cross-fades.
- Preserve scroll position during streaming unless the user is already pinned to the bottom.
- Prefer inline recovery states over generic alerts.
- VoiceOver order is header status, timeline in chronological order, composer controls, then secondary actions.
- Streaming announcements are coalesced; token-level updates are never announced individually.
- Tool start and completion are announced once each.
- Controller/viewer, offline, released, version-blocked, and error states are available as text, not color alone.
- Large accessibility sizes keep the composer usable and allow controls to wrap without clipping.
- Increased Contrast and Differentiate Without Color preserve every status distinction.

## Development Acceptance Checklist

- [ ] The production conversation, list, and settings surfaces use Jonwork product language and do not expose Pi Server, token, repository, session, runtime, CLI, provider, or protocol terminology in the normal journey.
- [ ] iPhone uses native push/pop navigation with a system back button and interactive back gesture.
- [ ] iPad and Catalyst use a native split view with one shared selection model.
- [ ] The conversation list comes from authoritative Jonwork summaries and distinguishes active, resumable, released, and unavailable conversations.
- [ ] Create, resume, switch, rename, search, and delete use authoritative Jonwork operations.
- [ ] The timeline reuses FlowDown message, Markdown/code, reasoning, and tool views rather than introducing a parallel renderer.
- [ ] Stable remote message and tool identifiers survive start, update, completion, reconnect, and snapshot replacement.
- [ ] Streaming text, reasoning, and tool progress do not visibly re-layout unrelated rows or move a user who has scrolled away from the bottom.
- [ ] The composer remains usable during streaming and requires an explicit Steer or Follow Up decision before sending.
- [ ] Viewer mode prevents every mutation, including send, stop, model change, rename, delete, release, and attachment upload.
- [ ] Takeover has pending, success, rejection, cancellation, and duplicate-tap behavior; it is disabled with an explanation while streaming.
- [ ] Stop ends the active run without deleting history and leaves the conversation resumable.
- [ ] Reconnect preserves the prior snapshot, replaces it from authority, then consumes new events.
- [ ] An unknown prompt or upload result is resolved with the original idempotency key and is never automatically duplicated.
- [ ] Retry names the exact safe operation and preserves the user's draft or attachment selection when appropriate.
- [ ] Attachments are shown only when the gateway capability and model support them and enforce type, count, byte, and timeout limits.
- [ ] Model, thinking level, and context usage come from Jonwork capabilities; legacy provider editing is unreachable.
- [ ] Released conversations disable mutation and provide a verified Back to Conversations action on compact and regular layouts.
- [ ] Version mismatch or missing required capabilities fail closed without partial conversation loading or stateless-chat fallback.
- [ ] All new user-visible strings use localization and ship in every supported locale.
- [ ] The production surface contains no FlowDown brand copy, proprietary artwork, legacy provider controls, MLX management, iCloud conversation sync, or MCP administration.

## Test Acceptance Checklist

- [ ] Deterministic reducer and presentation fixtures cover loading, empty, idle, streaming, offline, recovering, error, retry, viewer, takeover, released, and version-blocked states.
- [ ] Transition tests cover loading to empty/idle, idle to streaming to idle, and streaming to offline to recovering to an authoritative idle/streaming state.
- [ ] Ownership tests cover viewer to takeover pending to controller, rejection back to viewer, streaming takeover prohibition, and concurrent-writer prevention.
- [ ] Release tests prove the final snapshot remains visible, all mutation controls remain disabled, and Back to Conversations works on iPhone and Catalyst.
- [ ] Error tests cover authentication loss, authorization loss, timeout, malformed event, stream termination, unavailable model, unsupported attachment, and incompatible service version.
- [ ] Idempotency tests prove that an unknown create, prompt, upload, or retry outcome cannot produce duplicate user-visible mutations.
- [ ] Streaming replay tests cover text and reasoning deltas plus tool start, update, success, and error while retaining stable row identity.
- [ ] Attachment tests exercise every supported type and the type, count, per-file, aggregate-byte, conversion-timeout, and already-sent deletion limits.
- [ ] Search and rename remain correct after app restart and from a second authorized client, proving they are not local-only metadata.
- [ ] The critical conversation journey runs on the oldest supported iPhone class and a current flagship simulator or device.
- [ ] Every named state has accepted light- and dark-mode screenshots.
- [ ] A mixed text/reasoning/tool stream recording shows no visible relayout flash or unintended scroll jump.
- [ ] VoiceOver verification covers connect, send, stop, takeover, release, reconnect, retry, and version blocked; token deltas are not announced individually.
- [ ] Default Dynamic Type and AX5 remain usable without clipped status, navigation, composer, or action controls.
- [ ] Increased Contrast, Differentiate Without Color, and Reduce Motion preserve state meaning and task completion.
- [ ] Measured prompt-to-first-visible-update overhead is no more than 150 ms on a healthy local network.
- [ ] Reconnect to authoritative state completes within 3 seconds on a healthy network.
- [ ] Long mixed-content conversation scrolling targets 60 fps without repeated multi-frame stalls or unbounded message, Markdown, attachment, or tool cache growth.
- [ ] Production-surface inspection finds no FlowDown branding or excluded legacy capability entry point.

## Required Validation Evidence

- screenshots for every named state in light and dark mode;
- a screen recording of mixed text, reasoning, and tool streaming without visible relayout flash;
- a VoiceOver transcript for connect, send, stop, takeover, release, reconnect, retry, and version blocked;
- Dynamic Type screenshots at default size and AX5;
- measured scroll, first-update, and reconnect latency on the oldest supported device class;
- test records containing device, OS, app commit, gateway commit, steps, result, logs, and screenshots.

## Open First-Release Gates

The following first-release journeys remain blocked until they have implementation and independent device evidence:

- Rename must update the authoritative Jonwork conversation name rather than only local presentation metadata.
- Conversation search must define and use an authoritative Jonwork indexing source; local transient timeline rows are not a durable search index.
- Model, thinking level, and context usage need Jonwork-native controls before the legacy FlowDown selectors can be replaced. Pi-bound conversations currently hide the legacy selectors to prevent commands reaching the wrong backend.
- Image and file attachment controls remain hidden for Pi-bound conversations until the gateway accepts those payloads and enforces size, type, and timeout limits.
- Released conversations need a verified return-to-conversations navigation action on both compact iPhone and Catalyst layouts.
- The current connection model does not expose a complete recovering, retry, takeover-pending, or version-blocked presentation contract.
- iPhone still uses a custom drawer-style container rather than a native navigation stack.
- The production Jonwork gateway must expose a compatible version and capability contract for authoritative conversations, ownership, reconnect, and release; the client must not silently fall back to stateless chat.

Release packaging, signing, archive submission, and store-distribution work are outside this UX implementation phase.
