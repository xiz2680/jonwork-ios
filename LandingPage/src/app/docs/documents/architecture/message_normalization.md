# ChatClientKit Message Normalization (Compatibility)

This page explains how `ChatClientKit` “cleans” messages before sending requests to stay compatible with OpenAI-style, Anthropic, Mistral, and other interfaces. The sanitizer runs in `RemoteCompletionsChatClient`, `RemoteResponsesChatClient`, and the MLX client.

## Why the sanitizer is needed

- **Role alternation**: Some APIs strictly require user/assistant turns and reject empty content.
- **Tool responses**: Tool calls must be followed by matching tool responses, or APIs refuse to continue.
- **Strict mode**: Mixing tools with and without `strict` can trigger errors on some gateways.
- **Stability**: A unified message format makes retries and streaming recovery more predictable.

## Rule pipeline (execution order)

1. **Merge system messages**: Combine all `.system` messages into one, keep the first `name`, and filter out empty content. If the merged result is entirely empty, the system message is omitted.
2. **Fill missing tool responses**: For each `tool_call` inside an assistant message, if the matching `.tool` reply is missing, insert `.tool "."` with the same `toolCallID`, keeping the assistant→tool→assistant chain intact.
3. **Trailing user text**: If the final message is not user text, append `.user "."` so the model can continue after tool calls.
4. **Align strict tools**: If any tool declares `strict: true`, rewrite all tools to `strict: true` to avoid mixed-strictness errors.

**Note**: Placeholder content uses a single dot `"."` to satisfy minimum-content checks while minimizing semantic impact.
