# Configure Cloud Models

FlowDown supports any OpenAI-compatible HTTPS service (chat completions and responses). The app ships with dynamic templates—including pollinations.ai free models—so you can start chatting immediately or pull preset configs as needed.

## Fetch the latest templates

1. Open **Settings → Model**.
1. Tap the **＋** in the top-right corner.
1. Under **Cloud Model**, pick **pollinations.ai (free)** to fetch the latest anonymous text models with the correct endpoint and context, or choose **Empty Model** to start from scratch.
1. To reuse saved profiles, select **Import Model → Import from File** and load an exported `.fdmodel` or `.plist`.

![Fetch cloud model templates](../../../res/screenshots/imgs/cloud-model-pollinations-fetch.png)

Open the **Cloud Model** menu any time to refresh the pollinations.ai list or add a new blank profile; the list loads on demand.

## Connect your provider

1. Create a blank profile or open an existing one.
1. Enter the full inference URL (for example, `https://api.example.com/v1/chat/completions` or `/v1/responses`). FlowDown auto-detects and sets **Content Format**; switch it manually if detection is wrong.
1. Set the model identifier. Tap the field to **Select from Server**, which calls the model list endpoint (defaults to `$INFERENCE_ENDPOINT$/../../models`; adjust if your provider uses a different path).
1. Provide your provider credential/workgroup token (sent as a Bearer **Authorization** header) and any required headers. Custom headers can override Authorization for special auth schemes.
1. Add JSON in **Body Fields**. The quick menu inserts reasoning toggles (`enable_thinking` / `reasoning` with budgets), sampling parameters, input/output modalities, or provider flags.
1. Toggle capabilities (Tool, Vision, Audio, Developer role), set context length and nickname, then save.

> Tip: In the editor, `⋯` lets you **Verify model** (connectivity), **Duplicate**, or **Export model** for version control.

![Verifying custom model connection](../../../res/screenshots/imgs/cloud-model-verify-model.png)

## Best practices

- **Endpoint & format**: keep the inference URL aligned with **Content Format** (chat completions vs responses) to avoid HTTP errors.
- **Model list**: configure the model list endpoint and use **Select from Server** instead of typing IDs.
- **Pollinations**: free models are rate/region limited; connect your own provider if they are unavailable.
- **Body fields**: add provider-specific keys (reasoning budgets, `top_p` / `top_k`, modalities, etc.) via **Body Fields**, ensuring valid JSON.
- **Backups**: model definitions sync with iCloud and database exports. Before major edits, run **Settings → Data → Export Database**.

<a id="advanced-custom-enterprise-setup"></a>

## Advanced: Custom / Enterprise Setup

For private deployments or bespoke gateways. Connect only trusted endpoints—misconfigurations can leak data or incur costs.

- **Create**: **Settings → Model → ＋ → Cloud Model → Empty Model**. Edit inline or export `.fdmodel`, tweak externally, then re-import.
- **Key fields** (unused fields can be empty strings/collections):

  | Key                                             | Purpose                                                                                                         |
  | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
  | `endpoint`                                      | Inference URL such as `/v1/chat/completions` or `/v1/responses`; must match `response_format`.                  |
  | `response_format`                               | `chatCompletions` or `responses`, aligned with the endpoint.                                                    |
  | `model_identifier`                              | Model name sent to the provider.                                                                                |
  | `model_list_endpoint`                           | List endpoint (defaults to `$INFERENCE_ENDPOINT$/../../models`) for **Select from Server**.                     |
  | `token` / `headers`                             | Auth info; custom headers can override the default `Authorization: Bearer ...`.                                 |
  | `body_fields`                                   | JSON string merged into the request body—use it for reasoning toggles, budgets, sampling keys, modalities, etc. |
  | `capabilities` / `context` / `name` / `comment` | Declare capabilities, context window, display name, and notes to drive UI toggles and trimming.                 |

- **Verify & audit**: after saving, run `⋯ → Verify model`; audit calls in **Settings → Support → View Logs**. Remove/disable unused configs to avoid accidental calls.
