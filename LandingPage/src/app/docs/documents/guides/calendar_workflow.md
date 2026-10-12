# Calendar Planning

FlowDown includes on-device calendar tools for iOS, iPadOS, and macOS. When enabled, supported models can read availability, suggest times, and create or update events in your default calendar.

## Before you start

- Pick a tool-calling model (OpenRouter GPT-4o, Gemini Flash, etc.). If the current model cannot call tools, FlowDown will prompt you to switch.
- On first use, grant Calendar permission. If you see permission errors, re-enable it in **System Settings → Privacy & Security → Calendars**.
- For iCloud calendars, sign in to the system Calendar app with the same Apple ID. FlowDown never uploads calendar data to third-party servers.

## Enable tools in a conversation

1. Open or start a conversation.
2. Tap the **Tools** icon above the composer; the highlight indicates it’s on.
3. (Optional) In the conversation quick menu → **Conversation Settings**, set tools as the default for this thread.

## Ask the model to schedule

- Use natural language: “Plan a 30-minute demo next Tuesday afternoon” or “Find a free one-hour slot next week.”
- When the model prepares to create or edit an event, FlowDown shows a confirmation panel with details. Approve or reject each item.
- After approval, the event is saved to the default calendar and the conversation records the result.

## Troubleshooting

- **Permission denied**: reopen FlowDown after granting access, or toggle Calendar permission off/on.
- **Offline environment**: calendar tools use the local calendar database and can run offline, but cloud-dependent models may not reply without internet.
- **Repeated requests**: if responses loop, open the message menu → **Abort Tool**, then restate the request.
