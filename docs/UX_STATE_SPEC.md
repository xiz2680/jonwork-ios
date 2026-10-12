# Pi iOS Conversation Experience Specification

## Product Intent

Pi iOS is a calm professional control surface, not a generic chatbot. The active conversation is visually dominant. Navigation, ownership, model controls, usage, and recovery remain available without competing with the work.

The visual baseline is the existing FlowDown UIKit interface: native typography, generous spacing, translucent materials, stable Markdown layout, folded reasoning, compact tool cards, and a grounded composer. Existing components are reused before new UI is introduced.

## Conversation State Matrix

| State | Header | Timeline | Composer | Primary action |
|---|---|---|---|---|
| Loading | Session title placeholder and progress | Skeleton rows without layout jumps | Disabled | None |
| Empty | Repository and model context | Focused empty-state guidance | Ready | Send first prompt |
| Controller idle | Session title, controller badge | Authoritative history | Ready | Send |
| Controller streaming | Live activity and stop affordance | Stable text, reasoning, and tool updates | Ready for steer/follow-up | Steer or queue |
| Viewer | Viewer badge and current controller | Fully live | Read-only | Take over when allowed |
| Offline | Offline badge and last successful sync | Last authoritative snapshot | Disabled | Reconnect |
| Recovering | Reconnecting progress | Snapshot remains visible | Disabled | Cancel reconnect |
| Version blocked | Required/actual gateway version | No partial session | Disabled | Update server |
| Released | Released to CLI badge | Final snapshot | Disabled | Return to sessions |
| Error | Concise cause and request ID when available | Preserve safe content | Context-dependent | Retry safe operation |

## Interaction Rules

- Text submission receives immediate acknowledgement; the editor does not remain locked for an entire agent run.
- While streaming, the user explicitly selects **Steer** or **Follow Up**. The app never guesses delivery semantics.
- Stop is visible only to the controller. It stops the run without deleting session history.
- Takeover is disabled while streaming and explains why.
- Release explains that the mobile runtime closes while the durable session remains available to the Pi CLI.
- Reconnect replaces local presentation from the authoritative snapshot. An ambiguously delivered prompt is never resent automatically.
- Tool cards retain one stable identity from start through completion. Details are disclosed progressively.
- Reasoning is visually subordinate to the answer, folded by default after completion, and announced appropriately by VoiceOver.

## Visual System

- Use system semantic colors and materials; no hard-coded light-mode palette.
- Use Dynamic Type text styles and content-size-aware spacing.
- Maintain a minimum 44-point interactive target.
- Use SF Symbols by semantic name and pair status color with text/icon shape.
- Respect Reduce Motion by replacing spring/scale transitions with cross-fades.
- Preserve scroll position during streaming unless the user is already pinned to the bottom.
- Prefer inline recovery states over generic alerts.

## Accessibility Acceptance

- VoiceOver order is header status, timeline in chronological order, composer controls, then secondary actions.
- Streaming announcements are coalesced; token-level updates are never announced individually.
- Tool start and completion are announced once each.
- Controller/viewer, offline, released, and error states are available as text, not color alone.
- Large accessibility sizes keep the composer usable and allow controls to wrap without clipping.
- Increased Contrast and Differentiate Without Color preserve every status distinction.

## Evidence Required Before Release

- Screenshots for every state in light and dark mode.
- Screen recording of a mixed text/reasoning/tool stream with no visible relayout flash.
- VoiceOver transcript for connect, send, stop, takeover, release, and reconnect.
- Dynamic Type screenshots at default and AX5.
- Measured scroll and first-update latency on the oldest supported device class.
