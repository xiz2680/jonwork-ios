# XIZ-134 current Home parity matrix

Current requirement authority: Linear XIZ-134 top “latest execution requirements”, retrieved 2026-10-14. This section supersedes the historical Pi Mobile inventory below. Source baseline: iOS `0df24481a32eac634ed65fad2ac2a8800b86cbbb` plus protected dirty work; gateway `22869e9cb847c64226219d108c178391b52151d9`; DeepTutor `2c0a9778b5ee18e984dfae5c91ce48c2b5c61b63`. Stage2 implementation is active; this matrix records Stage1 findings and must be updated against the final frozen source before acceptance.

Evidence root outside Git: `/tmp/xiz134-20261014`. Actual Home audit: `home/stage1-home-audit.md`; independent native audit: `verify/stage1-native-audit.md`; Home source matrix: `home-feature-matrix.md`; independent review: `review/stage1-independent-review.md`. Account screenshots, recordings, credentials and user session data are not committed. Old test results below never establish current acceptance.

Classifications explicitly distinguish webpage existing/reachable, conditional capability, native extension and interface gap. Source-existing is not live passed. The table preserves first-pass status: N-001 blocked every original installed-native authenticated journey. A separately reviewed auth-only diagnostic binary later recovered an existing real viewer conversation, image preview and settings baseline without entering credentials; it does not prove fresh login or final redesigned-app acceptance. None inherit Home/API/fixture success. “Pending” means authorized implementation remains; “gap” is a required contract, not an omitted feature.

Current backend source increment: gateway `71659b7fd435b2d4dbe64b17d5a21970ed78da64` (319 tests passed and full typecheck), DeepTutor `1dc8263c9bfdf73f5584bc0b4a5471d055087e90` (247 affected Python tests and 11 web tests passed, Ruff/full web TypeScript passed; five unresolved Python warnings plus teardown warning). Both commits are pushed to existing PRs. Home1 consent-bound history/snapshot/persisted-event reads and Pi creation/attachment guards are implemented and independently reviewed at these hashes; common Home writes remain blocked pending shared admission. No deployment, hosted W-001/W-002 repair acceptance or final native acceptance is claimed. See [execution evidence](XIZ134_EXECUTION.md) for exact evidence and remaining gates.

| Required capability | Actual Home / classification | Native or contract status at first pass | Final evidence obligation |
|---|---|---|---|
| First-run guide | Source existing; live first-run unverified | Native source existing | No reset performed; final native required |
| Unified browser login / cancellation | Authenticated Home existing; browser-login source | Native FAILED N-001; PKCE existing | Known rebuilt binary + callback required |
| Credentials restore / expiry / relogin | Conditional existing auth | Native blocked N-001 | Account generation/Keychain/revoke verification |
| Personal / enterprise identity | Live identity chooser reachable | Interface gap at first pass; scoped Home read delegation now committed | Main-issued consent handle fixes subject/workspace/membership; final native required |
| Identity / account switching | Conditional Home source | Interface gap; native blocked | No client-chosen identity authority; old request fencing |
| Text chat / multiturn / streaming | Live new send/reply passed; multiturn unverified | Pi source existing; native blocked | Home runtime differs from Pi; real E2E required |
| Research mode | Live report+quick outline; continuation FAILED W-002 queue2/5 | Interface gap | Actual deep_research runtime, no prompt-label substitute |
| Visualization mode | Live Mermaid pipeline/render/code/fullscreen passed | Interface gap | Actual visualize runtime/result schema |
| Voice input | Home STT conditional provider/permission | Native dictation reused; unverified | Native extension differs from Home STT |
| Image input / preview / removal | Home source conditional | Pi model-gated images source; native blocked | Real picker + consent + limits + upload proof |
| Document input / preview / removal | Home asset source conditional | Interface gap: discovery files=false | Reuse authorized Home assets/extractor; not image flag toggle |
| Sent attachment previews | Home source conditional | Partial filename projection / interface gap | Scoped bounded downloads and stale-preview cancellation |
| History references | Live picker and actual sessions | Interface gap | Owner/workspace-filtered readable session IDs |
| Agent history references | Live menu; configured Agent sessions conditional | Interface gap | Distinct from connected Agent execution |
| Connected Agents | Home source conditional | Interface gap | Real permission/config and progress contract |
| Knowledge references | Live two authorized choices | Interface gap | Personal/enterprise availability; execute permission recheck |
| Role/persona references | Live chooser: default only for this identity | Interface gap | Do not invent persona options |
| Memory references | Source conditional | Interface gap | Scope/data/permissions required |
| Notebook/book/question references | Source conditional | Interface gap | Permission-filtered resource catalogs |
| Message rendered copy | Live control; copy execution unverified | Native source existing | Final actual clipboard content required |
| Original-source copy / share | Requested native extension | Native safe read-only source | Authoritative current identity; share explicit action |
| User edit / branch preservation | Live edited smoke branch2/2; original1/2 preserved | Interface gap | Stable parent/message IDs; revision/idempotency/lease |
| Assistant regenerate | Live regenerate completed for smoke branch | Interface gap; Pi retry is not regenerate | Original context/attachments/references preserved |
| Assistant read aloud | Live control; Home TTS conditional | Native extension / integration pending | Native speech distinguish Home provider parity |
| Delete a message / turn | Live control; Home source deletes turn | Interface gap | No local history rewrite; destructive test evidence separate |
| Create / switch sessions | Live Home new session passed; switch source | Pi native source; create race R2 | Must list actual Home histories to claim parity |
| Session search / rename / delete | Live controls; source existing | Pi source existing; native blocked | Remote receipt/revision; no local projection substitute |
| Save notebook | Live modal; no notebook for current identity | Interface gap; conditional dependency | Save disabled correctly; no invented destination |
| Whole Markdown export | Live actual download223B checked | Native implementation pending | Current authoritative visible branch only |
| Selected / single Markdown export | Selected assistant download114B checked | Native implementation pending | Selection/message scope preserved |
| Whole / selected PDF export | Whole FAILED W-001 chunk load; selected unverified | Native implementation pending | PDF parser/layout/output plus final native evidence |
| Image output view / save / share | Home source conditional | Native bounded output-image loader source | Actual image output/preview still native blocked |
| Code / table output | Home source existing | Native Markdown/Runestone reuse | Final rendered copy/accessibility required |
| Document output | Home asset/viewer source conditional | Interface gap plus native QuickLook reuse | Real MIME/type/size/authenticated assets |
| Chart / interactive webpage output | Home source conditional; frame policy may block | Interface gap | Isolated untrusted scripts / explicit browser fallback |
| Sources / citations | Home request/result source conditional | Interface gap / partial Markdown links | Actual provenance; no fake sources |
| Reasoning / tool progress | Live completed state; source wired | Native reasoning/tool components source | Stream stable IDs + long expand/collapse proof |
| Agent / subagent progress | Home source conditional | Interface gap | Real attribution/grouping/cursor/replay |
| User clarification | Home ask_user source conditional | Interface gap | Paused turn/question IDs/idempotent reply/stale rejection |
| Stop / error recovery / reconnect | Observed live pending Stop; execution unverified | Pi native source | Home wrap real turn; no duplicate ambiguous prompt |
| Usage / calls / context | Live1.7k tokens/1call; missing data conditional | Interface gap | Unknown remains unknown; no sample count/zero fabrication |
| Controller / viewer / lease | Home shared admission gap | Pi lease source; R2 exception | Web and native must share mutation boundary |
| Settings root | Live real Home settings | Native settings source to adapt | Six-state design and navigation acceptance |
| Model / AI current-session config | Home different registry; native position requirement | Chat selector violates R4; development | ONLY Settings; settled authoritative confirmation |
| Model / AI scoped defaults | Requested native extension/config scope | Implementation pending | Account/workspace isolation, actual supported models |
| Logout cancel / confirm | Home source; not executed | Native cleanup source; rendered purge risk | No old-content return; cloud sessions retained |
| Authorization revoke / local purge | Home/source conditional | Native source plus R1 redirect/origin fixes | Late refresh/auth/request isolation tests + E2E |
| Search / favorite / pin | Search source; favorites/pins native extension | Native implementation pending | Scoped metadata, no claim of web sync |
| Draft recovery | Native extension | Existing memory-only text; development | Identity/workspace/session isolation; attachment/cold limits explicit |
| Light / dark / Dynamic Type | Native extension requirement | Login themes + one text increment partial | All six final states still blocked/unverified |
| VoiceOver / Reduce Motion / haptics | Native extension requirement | Source hooks; runtime unverified | AX is not VO; haptics physical-only |
| Keyboard / long session / background | Native requirement | Source hooks; runtime blocked | Streaming scroll/follow/latest/reconnect final proof |
| Seven locales | Native requirement | Development checks pending | en,de,es,fr,ja,ko,zh-Hans final Makefile checks |
| Motion before/after | Native requirement | Login baseline36.933s captured | Authenticated motion baseline and final blocked |
| Physical device / oldest/current classes | Native requirement | No physical evidence; one verifier simulator | Record device and simulator separately; no all-pass |

## Historical Pi-only source inventory

Retained for traceability. Its scope, model-placement advice and old acceptance claims are superseded by the table above and final XIZ-134 evidence.

# Conversation feature matrix

Source audit: 2026-10-14. Native baseline `0df24481a32eac634ed65fad2ac2a8800b86cbbb`; Pi Web baseline `4cc9b712254d84c90a00373c972c8a417fd26fb9`; gateway baseline `7dce094fb3b5b44f110d791a1be56d52913bfb3a`. This report is a baseline, not acceptance of concurrent UI changes.

## Evidence boundary

This pass inspected source and existing test definitions only. It did not run builds, tests, a browser, simulator, production requests, or Mobbin inspection. The coordinating agent reports that production authentication and real chat were verified; no individual feature below inherits that result automatically. Native interactive acceptance, visual consistency, accessibility, and current-HEAD test execution remain unverified. A test file is evidence of coverage intent, not evidence that the test currently passes. No feature is marked fully verified by this audit.

`Implemented` means a reachable production Pi path exists in source; `Partial` means part of the journey exists; `Missing` means no matching production path was found; `Unsupported` means the inspected gateway explicitly lacks the capability. All implemented entries remain runtime-unverified in this pass. Pi Web is the local `pi-mobile` application using `/api/*`, not the production OAuth `/v1/*` gateway; its behavior is a comparison, not a compatible protocol fallback.

Paths below are relative to these exact roots:

- Native (N): `/Users/a/workspaces/personal/jonwork-ios`
- Web (W): `/Users/a/xz-workspace/jonwork2.0/pi-mobile`
- Gateway (G): `/Users/a/workspaces/personal/jonwork-server`

## Source index

| ID | Source |
| --- | --- |
| N1 | `Jonwork/Interface/ChatView/ChatView.swift:384-660` (capability-gated editor and session actions) |
| N2 | `Jonwork/Interface/ChatView/ChatView+Delegates.swift:139-292` (send, steer/follow-up, consent, attachment inputs); later draft callbacks |
| N3 | `Jonwork/Backend/Pi/PiSessionCoordinator.swift:309-449,450-618,620-1159,1181-1255` (connection, commands, upload, projection) |
| N4 | `Jonwork/Interface/SettingController/Pi/PiServerController.swift:48-278,290-556` (workspace/repository/session browser, search, delete, sign-in) |
| N5 | `Jonwork/Interface/ConversationSelectionView/ConversationSelectionView.swift:129-187`; `+Delegate.swift:18-104`; `+Cell.swift:90-109` (local sidebar) |
| N6 | `Jonwork/Interface/MessageListView/MessageListView+Adapter.swift:250-500` (tool detail and message menus) |
| N7 | `Jonwork/Backend/Pi/PiSessionReducer.swift:1-46,150-225`; `PiEventAdapter.swift` (stable transcript and events) |
| N8 | `Jonwork/Backend/Pi/PiGatewayWire.swift:275-330` (production snapshot and attachment schema) |
| N9 | `Jonwork/Interface/ChatView/PiSessionStatusView.swift:57-86` (ellipsis and stop only) |
| N10 | `Jonwork/Interface/Sidebar/Sidebar+Delegates.swift:18-32`; `Jonwork/Interface/ConversationSearchController/SearchContentController.swift:117-126`; `Jonwork/Backend/Conversation/ConversationManager+Search.swift:12-51` (local search) |
| N11 | `Jonwork/Interface/MessageListView/MessageListView.swift:53-58,146-156,180-216,224-275`; `MarkdownOutputImages.swift`; existing MarkdownView/Runestone integration |
| N12 | `Jonwork/Interface/RichEditor/RichEditor/RichEditorView+Object.swift:99-150`; `Jonwork/Interface/ChatView/ChatView+SharingConsent.swift`; `Jonwork/Backend/Pi/PiSharingConsent.swift` |
| W1 | `public/app/main.js:75-205,228-315` (metrics, controls, text composer/keyboard) |
| W2 | `public/app/ui/sidebar.js` (active/repository/saved sessions, new session, add repository) |
| W3 | `public/app/ui/menu.js:93-260` (model search and thinking selection) |
| W4 | `public/app/session/controller.js` (SSE, attach/resume, takeover/abort/release); `chat_view.js`; `tool_boxes.js`; `content.js` |
| W5 | `src/session-runtime.ts:90-125,385-451` (stats/context and command handling); `public/app/session/cli.js` |
| G1 | `apps/api/src/pi-gateway/http.ts:10,31-65` (discovery, endpoint/command allowlist, permissions, attachment limits) |
| G2 | `apps/api/src/pi-gateway/runtime.ts:75-106` (prompt, steer, follow-up, compact, model/thinking, retry and image inputs) |
| G3 | `apps/api/src/pi-gateway/store.ts` (session grants/list/search/delete, snapshot, durable mutation and replay) |
| G4 | `apps/api/src/pi-gateway/auth.ts`; `browser-login.ts`; `apps/api/tests/pi-gateway.test.ts` (OAuth and fixtures) |

## Full journey inventory

| Feature / user outcome | Native source status | Pi Web comparison | Gateway status / evidence | Priority / acceptance needed |
| --- | --- | --- | --- | --- |
| Sign in to the provisioned workspace | Implemented, N4, PiOAuth / NativeSignIn | Token/Face ID local web flow; different auth | Implemented G4; production success coordinator-reported | P0: native cancellation, callback, expiry, sign-out journeys |
| Restore saved credentials / sign out | Implemented N4; Keychain and revocation | Local storage / Face ID guard | OAuth refresh rotation/revoke G4 | P0: cold-launch and revoked account |
| Repository selection | Implemented N4 | Implemented W2 | Scoped repository list G1/G3 | P1: integrate current repo clearly in sidebar |
| Add arbitrary repository | Not a normal native action | Implemented W2 prompt | No repository-creation endpoint in Pi gateway | P2: administrator provisioned repos; do not fake capability |
| New conversation | Implemented N4; header new-chat entry | Implemented W2 | Create session G1/G3 | P0: no accidental duplicate create, coherent sidebar entry |
| Resume server conversation | Implemented N4/N3 | Implemented W4 saved-session resume | Restore endpoint G1/G3 | P0: authoritative history and ownership |
| Switch conversation | Implemented N5/N3 | Implemented W2/W4 | Multiple sessions supported | P0: streaming session switch/cancellation |
| Server history versus opened local history | Partial: server list N4, sidebar only local ConversationManager N5 | Active, repos and saved repo sessions W2 | Authoritative server list G3 | P1: single coherent navigation, unopened sessions discoverable |
| Session title / rename | Implemented N1/N4 | Displays name/first prompt W2; no rename UI found | PATCH session G1 | P1: rename from sidebar with server receipt |
| Search conversation titles/history | Partial: server search N4; sidebar search reads local storage N10 | No conversation-search UI found; model search W3 | Session query supported G1/G3 | P1: sidebar must route to server search; transient Pi body absent from local DB |
| Conversation delete | Implemented only in server browser N4; Pi sidebar swipe/menu disabled N5 | No delete UI found | Authorized session delete G1/G3 | P1: expose same confirmed remote deletion from sidebar |
| Pin/favorite conversation | Missing for Pi; legacy favorite explicitly gated N5 | Not found | No pin API | P2: possible local metadata, scoped to user/workspace, no implied remote sync |
| Date grouping / recent ordering | Partial N5 groups by local creation; does not use server updatedAt | Relative modified times and active state W2 | Server updatedAt available G3 | P1: stable sort by activity; deterministic within groups |
| Active/running/released row states | Partial: server browser state labels N4; sidebar cell only title/icon N5 | Working metadata W2 | Snapshot/list state G3 | P1: show meaningful session state with accessibility |
| Empty/loading/list-error states | Implemented in server browser; generic native shell | Sidebar failure W2 | Typed API errors | P1: device visual acceptance |
| Multiline text composer / send | Implemented N2/N12 | Implemented W1 Enter/Shift+Enter | Prompt G1/G2 | P0: keyboard, disabled viewer and send race |
| Draft retained after cancelled consent / failed send | Implemented completion(false) N2/N12 | Input cleared around text submission; audit no failure guarantees | Client responsibility | P0: native cancel/error proof |
| Per-session draft save/restore | Missing Pi-specific path: N2 draft callbacks return for bound Pi sessions | No scoped persisted draft found | Client responsibility | P1: preserve text/attachments across switch and background; do not persist transcript accidentally |
| Attachment picking/removal before send | Implemented picker and capability intersection N1/N2/N3 | No attachment composer found | Images supported, model-gated G1/G2 | P1: photo/camera/file-picker image journeys, denied permission |
| Image size/count/type constraints | Implemented N3; max 10MiB each, 20MiB aggregate, four images | Not found | Same caps, PNG/JPEG/WebP G1 | P0: rejection and retries do not duplicate upload |
| Generic documents / PDF / arbitrary files | Unsupported current gateway, picker must remain gated | Not found | Explicit `files:false`, runtime rejects non-images G1/G2 | P1 contract gap: cannot fulfill generic files in client alone |
| Attachment upload retry / consent fencing | Implemented N3/N12, retained idempotent receipts | Not found | Upload + receipt paths G1 | P0: existing focused tests, rerun at final HEAD |
| Sent/history attachment preview/open | Partial: N7 converts attachment to filename-only row; N3 render never hydrates preview | Not found | Metadata/content route exists G1 | P1: real authenticated content preview and safe expiry/failure states |
| Assistant text streaming / multi-turn history | Implemented N3/N7/N11 | Implemented W4 | Live delta/snapshot G2/G3; production chat reported verified | P0: native real timeline test still pending |
| Markdown / code / tables / math / links | Implemented existing native renderer N11 | Markdown W4 and render/markdown.js | Opaque untrusted output | P1: visual fixtures, copy code, link confirmation |
| Assistant output images | Implemented MarkdownOutputImages constrained loader | Markdown renderer comparison | External Markdown URLs, not gateway-generated asset guarantee | P1: redirect/local-network policy and accessibility acceptance |
| Streaming reasoning | Implemented N7, ReasoningContentView | Implemented W4 | Reasoning deltas G2 | P1: empty/no-reasoning and long reasoning |
| Tool start/update/success/error | Implemented stable tool cards N7 | Implemented tool_boxes W4 | Tool events G2 | P0: real tool failure and long output |
| Tool arguments/raw result/details | Partial: N6 details uses legacy request decoder; Pi projection stores tool status/detail, not full legacy request JSON | Expandable W4 tool cards | Detail strings/events; no separate full artifact endpoint | P1: avoid "Unable to decode" for normal Pi tools; cap/truncation disclosure |
| Nested tool attribution | Domain carries parentCallID N7; dedicated nested visual hierarchy unverified | Tool rendering W4 | Events include parent identity | P1: inspect real nested fixture on device |
| Send steering while active | Implemented explicit chooser N2 | Runtime allows steer; default UI follow-up W1/W5 | Supported G1/G2 | P0: exactly one accepted prompt |
| Queue follow-up while active | Implemented chooser N2 | Implemented default W1/W5 | Supported G1/G2 | P0: accepted/pending/completed visible without duplicate rows |
| Inspect/reorder/remove queued prompts | Missing | No queue editor found | No queue-management API | P2: cannot promise editing/removal without contract |
| Queue all versus one-at-a-time mode | Missing production UI/API | Runtime set_steering_mode/set_follow_up_mode W5, no main menu found | Not in gateway command allowlist G1 | P2 backend contract gap |
| Stop current response | Implemented visible stop + action N1/N9 | Implemented W1/W4; local web viewer abort differs | Controller-only abort G1/G2 | P0: preserve history and resume |
| Retry failed response | Implemented session-action retry N1/N3 | No dedicated retry UI found | Only failed/aborted **prompt** retry G2 | P0: attachment retry preserves original content; see gap below |
| Regenerate successful historical answer | Missing real Pi semantics; legacy menu exposed incorrectly N6 | Not found | Retry forbids settled successful source G2 | P0 remove misleading legacy action; later versioned capability |
| Edit earlier prompt / branch conversation | Missing Pi semantics; legacy Redo/Edit exposed incorrectly N6 | Not found | No branch/edit-message endpoint G1 | P0 remove local transcript mutation; P2 design/backend work |
| Delete a single message / truncate after it | Legacy UI incorrectly exposed N6 | Not found | No message deletion endpoint G1 | P0 hide for Pi; retain whole-session deletion only |
| Rewrite/translate selected answer | Legacy generic-provider Rewrite incorrectly exposed N6 | Not found | No dedicated endpoint; could be explicit new prompt later | P0 hide legacy provider execution |
| Copy message / view raw / share text | Implemented N6 | Native browser selection; no custom actions found | No API needed | P1: retain these safe read-only actions |
| Copy rendered message as image | Implemented N6 | Not found | Client-only | P2: long content image export/permission acceptance |
| Export entire conversation | Missing Pi-specific export | Not found | Snapshot could support explicit client export; no export endpoint | P2: privacy-aware export if required, no legacy cached transcript |
| Select model | Implemented N1, settlement + authoritative confirmation N3 | Searchable model menu W3 | Supported G1/G2 | P0: changes pending/succeeded/failed; P1 current model visibility |
| Select thinking depth | Implemented N1, model-level choices | Implemented W3 | Model-gated G1/G2 | P1: localized level display and unsupported model |
| Show current model / reasoning in ordinary header | Partial: checked submenu only; N9 no status labels | Visible selectors and footer W1 | Snapshot config present | P1: concise accessible current model control |
| Compact context | Coordinator implemented N3:531; no ChatView action | Automatic compaction runtime events; no manual UI found | `compact` supported G1/G2 | P1 safe addition with confirmation and consent review |
| Token/cost/cache/context usage | Missing production UI/schema; old types alone do not count | Implemented footer W1/W5 | v1 snapshot/events lack usage fields G1/G3/N8 | P1 backend extension required; never display guessed counters |
| Controller/viewer and takeover | Implemented gates/actions N1/N3; N9 has no persistent role label | Visible role pill W1, takeover W4 | Single-writer/takeover G1/G3 | P1 visible role/recovery context before disabled composer |
| Release to desktop | Implemented confirmed action N1/N3 | Implemented W4 with CLI command W5 | Release G1/G3 | P0: released composer disabled and durable history |
| Copy precise desktop resume command | Missing native production sessionPath in snapshot | Implemented cli.js W5 | Snapshot omits host filesystem path | P2 safe deep link/server-provided resume intent, no guessed path |
| Offline/reconnect / expired SSE cursor | Implemented N3 and retry menu N1 | Browser EventSource reconnect W4 | Replay IDs/snapshot G1/G3 | P0: authoritative replace, no duplicate send |
| Background/foreground / cold restart recovery | Implemented lifecycle and pending store paths | Browser connection recovery | Durable gateway records | P0: simulator/device acceptance pending |
| Visible thinking/waiting/retrying/error state | Partial: stop indicates active; state has failure but N9 only changes ellipsis accessibilityHint for offline | Working spinner/role/footer W1 | Events/retry status | P1: compact state label and actionable typed error |
| Auto-scroll / preserve user reading position | Implemented N11 | Chat auto-scroll W4 | Client-only | P1: long mixed timeline performance and jump-to-latest discovery |
| Voice recording / spoken answer | Not a production Pi feature | Not found | No audio inputs/TTS capability | P2 explicitly out of current gateway scope |
| Accessibility / light-dark / Reduce Motion / seven locales | Existing components have hooks, status actions 44pt N9 | Web separate UX | Client-only | P0 acceptance: VoiceOver, largest type, keyboard, contrast; source hooks are insufficient evidence |
| Consent revoke / account/workspace boundaries | Implemented N12/PiServerDomainCoordinator | Different local web auth/privacy model | OAuth principal boundaries | P0 confirm no uploads after revoke/scope change |

## Prioritized gaps and smallest safe changes

### P0 — remove misleading or destructive Pi actions

1. **Historical message menus cross the backend boundary.** `MessageListView+Adapter.swift:358-500` creates Retry, Redo(Edit), Rewrite, Edit, Delete and Delete w/After for every rendered message without a Pi binding check. `ConversationSession.swift:253-267` truncates local state; `:371-403` retries via legacy model configuration, including an assertion when `models.chat` is nil. These actions neither mutate authoritative gateway history nor honor Pi controller/consent semantics. Viewer mode does not gate them. Minimum repair: branch the menu for Pi-bound sessions and retain Copy, View Raw, Share, Copy as Image and tool details; expose only supported coordinator actions. Do not route successful-answer regeneration to failed-operation retry.

2. **Attachment-bearing failed prompt retry is text-only in the inspected gateway.** `G2 runtime.ts:95` reads the original failed prompt request then calls `session.prompt(original.text)`, ignoring original attachmentIds/images. The upload path consumes attachment rows at `:104`; simply re-running promptContent would reject consumed IDs. Minimum backend repair: retain authenticated original content for operation retry or reload session-consumed attachment rows with the correct session/user/repository scope. Add a failing-image-prompt retry fixture proving image bytes and ownership are preserved. Until fixed, do not promise equivalent retry for image prompts.

3. **Native full acceptance remains outstanding.** Existing protocol and reducer tests do not demonstrate a coherent sidebar, actual real chat rendering, permissions, or release readiness. Verify final commit rather than the baseline after implementation.

### P1 — indispensable coherence and conversation completeness

- Unify native sidebar with the existing server-backed repository/session/search/delete paths (N4). Local search N10 cannot search transient server messages. Avoid a second competing session list hidden in settings.
- Add isolated per-session draft retention, including attachments, with explicit privacy/lifetime policy. N2's restore/update callbacks intentionally skip Pi; cancellation in the current editor is not cross-session draft persistence.
- Make role, current model/thinking and connection/error state visible in the existing header/composer. Keep advanced controls in the existing menu. Do not rely on the ellipsis accessibilityHint to communicate offline status.
- Add manual context compaction using the existing coordinator, only idle controller state, confirmed effect, error/pending presentation, and consent validation because compaction may share conversation content with a provider.
- Render authenticated sent/history attachments through the existing attachment component with expiry and download limits. A filename row is not image preview support.
- Show real usage/context only after extending the gateway schema and fixtures. Generic file support likewise requires backend implementation and advertised limits, not an enabled picker.
- Repair Pi tool details using domain fields actually supplied by the gateway instead of pretending the legacy decoder has the original tool request.

### P2 — explicitly scoped follow-ons

Pin/favorites, full export, branch/edit/regenerate, queue reordering/removal, queue mode controls, audio and precise desktop resume require product/contract decisions. The matrix preserves them as explicit missing/unsupported items; they must not disappear from the checklist or become fake controls.

## Existing meaningful automated coverage (not executed here)

- `JonworkTests/PiSessionCoordinatorTests.swift`: suspended upload authorization invalidation, upload receipt recovery, ambiguous mutation receipts, session-switch generation fencing, viewers, model/thinking settlement and reconnect.
- `JonworkTests/PiSessionReducerTests.swift`, `PiGatewayV1Tests.swift`: stable event reduction, snapshot projection and wire fixtures.
- `JonworkTests/PiTransientTimelineTests.swift`: Pi messages excluded from persistent storage.
- `JonworkTests/PiSharingConsentTests.swift`, `PiOAuthAuthorizationTests.swift`, `PiAuthenticationFlowTests.swift`: authorization, identity and consent boundaries.
- `G apps/api/tests/pi-gateway.test.ts`: real HTTP/SQL gateway fixtures, contracts, grants, attachments and durable session operations. Presence does not establish image-preserving failed-operation retry.

Final native verification should record device/OS, native and gateway commit, screenshots and observed outcome for connect, new/resume/switch, text/image streaming, tools/reasoning, steering/follow-up, abort/retry, offline recovery, viewer/takeover/release, search/delete/rename, draft retention and accessibility. Mark each as passed, failed, blocked or not tested. Build/unit execution remains through the Makefile; no build was run in this audit.

## Follow-up implementation after the baseline audit

The delegated implementation now gates Pi message menus to Copy, View Raw, Share and Copy as Image; tool details use actual gateway detail rather than the legacy parameter decoder. Pi text drafts are scoped by workspace/repository/session/connection and retained in memory across session switches and background/foreground. They are cleared on unbind/authentication revocation, contain no attachment bytes, and intentionally do not survive process termination. `compact` now accepts a sharing authorization fence; its menu entry is owned by the coordinating UI implementer. These are source changes, not verified UI/build results; re-run final-HEAD tests and journeys before upgrading matrix statuses. Attachment drafts, history image previews, server-backed sidebar search and usage remain explicit gaps.

## Exit and account switching acceptance

| Exit journey | Source result and required evidence |
| --- | --- |
| Explicit sign out | Domain signOut revokes consent, invalidates credential provider, cancels login/network, clears presentation/bindings/transient timeline/drafts/pending mutations, then revokes refresh/access tokens and removes Keychain tokens. UI entry is being added by the coordinator's UI implementer. |
| Sign out from a fresh account menu | Fixed no-oauthContext path: discover without credentials, validate discovery and exact revocation origin, use a noninteractive authorizer. Discovery/revocation failure still removes local credentials and reports failure; server-side revocation is not falsely claimed. New regression fixtures cover success/failure/cross-origin rejection. |
| Switch account | Must pass through sign out and fresh sign-in; do not reuse old session bindings, drafts, consent, credential factory or timeline. A same-device clientID is not itself an account identifier; clearing the authenticated session is required. |
| Cancel sign-in | Authentication generation/cancellation tests exist. Verify returning to the login screen with no established session and no error presented as a successful login. |
| Dismiss current chat / open sidebar | Navigation only, not sign out or automatic release. Preserve scoped draft and choose whether the same active SSE remains alive according to coordinator lifecycle. Do not conflate closing a screen with deleting a conversation. |
| Disconnect / offline | Disables mutation until authoritative reconnect. Does not erase identity or pretend the server token is revoked. |
| Background / foreground | Existing lifecycle suspends/refetches active state; memory-only text draft survives while the process remains alive. Verify no background-generated duplicate prompt. |
| Process restart after sign out | No token restoration; previous account session/draft/consent must not become editable. Text drafts are intentionally absent on process restart. |
| Continue on Desktop / release | Separate confirmed runtime release; not account sign out. Preserve server transcript and stop native mutations. |

All exit journeys remain native interactive-unverified in this audit. The existing microphone performs platform speech-to-text before sending ordinary text, per UI implementer source review; this does not imply gateway audio attachment or spoken-answer support.
