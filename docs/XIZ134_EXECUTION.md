# XIZ-134 execution and evidence

Requirement authority: the latest execution section at the top of [XIZ-134](https://linear.app/xiz2680/issue/XIZ-134/jonwork-ios新版会话界面原生动效与-home-功能对齐). Historical design-only and Pi-only records are superseded. The task excludes an App Store submission.

## Independent roles and resources

The coordinator verified `HERDR_ENV=1` and found only the existing coordinating agent. Four new Codex roles started with the requested `gpt-6.1-sol`, medium reasoning, never approval and danger-full-access flags; all accepted their assignments. No existing agent was restarted.

| Role | Herdr agent / pane | Ownership / resources |
|---|---|---|
| Coordination | Existing agent, `wJ:p1` | Requirements, matrix, issue tracking, Linear, focused integration and PR updates |
| iOS implementation | `x134-ios`, `wJ:p2` | Native app/tests/localization/Makefile; `/tmp/xiz134-dd-ios`; unit simulator `ADB11570-B253-4469-B5A1-1DE855B3738D` |
| Home/gateway implementation | `x134-home`, `wJ:p3` | Gateway and necessary DeepTutor adapters/runtime repairs; no simulator UI |
| Independent review | `x134-review`, `wJ:p4` | Review evidence only; no product source changes or native UI |
| Independent verification | `x134-verify`, `wJ:p5` | Native evidence only; simulator `58B87661-684D-4904-AE48-4FD705E8A247`; `/tmp/xiz134-dd-verify`; exclusive Simulator UI |

Existing iOS dirty work was recorded and backed up before changes, including untracked source/tests/docs. Gateway and DeepTutor started clean. No reset, clean, unrelated change overwrite or production deployment was authorized by this execution record. Account screenshots, session data, recordings and build logs remain outside Git.

## First-round source and actual interface evidence

Evidence root: `/tmp/xiz134-20261014`.

- `baseline/`: initial SHA/status/patches and protected untracked files.
- `ios/stage1-native-plan.md`: UIKit reuse and source animation inventory.
- `verify/stage1-native-audit.md`: independent installed-native audit and every blocked/unverified scope item.
- `verify/baseline/`: inspected screenshots and 36.933-second login animation recording.
- `home/stage1-home-audit.md`: actual authenticated Home steps, screenshots, downloads and failures.
- `home-feature-matrix.md`: actual DeepTutor Home source contracts and permission conditions.
- `review/stage1-independent-review.md`: independent actionable findings and per-repository dirty digests.

Installed initial app: `com.jonwork.ios`, version 1.0.0 (1), executable SHA-256 `8e2acf38b829784cad398969741a6cc4ce069731f19a99a5c395d307a20d8e8e`. Its source commit was not established. Current working-tree HEAD must not be used as installed provenance.

Actual Home evidence confirms a new chat response and real usage, whole and selected Markdown downloads, edited branch preservation, assistant regeneration, and Mermaid pipeline/render/code/full-screen behavior. Notebook saving was conditional because this identity had no notebooks; persona selection exposed only the default. Reference and mode controls alone do not prove successful resource use.

## Unified issue and repair tracking

| ID | Trigger / impact | Repair and acceptance state |
|---|---|---|
| N-001 | Original native browser consent opens a blank sheet, then a generic unavailable error | Reviewed diagnostic binary recovered an existing real native conversation without credential entry. Original failure phase and fresh browser login remain unverified; this is not final redesigned-app acceptance. |
| R1 | Discovery can direct credential endpoints to another origin; default HTTP redirects can forward sensitive POST bodies | Central origin checks and redirect rejection under implementation; real two-origin tests and final source review still required. |
| R2 | Create-session receipt written after asynchronous attach can duplicate same-key sessions | Durable creation reservation/recovery, restart and failure tests implemented in gateway commit `71659b7`; independent scoped source review mapped to that commit. |
| R3 | Attachment download omits current repository/expiry checks; upload permissions can change during body read | Current repository/grant/expiry checks and serialized, post-body authorization guards implemented in gateway commit `71659b7`; independent scoped source review mapped. |
| R4 | Model/thinking selectors remain in chat actions | Move all configuration to Settings > Model & AI; preserve pending/settled authoritative semantics. Final six-state UI unverified. |
| R6/R7 | Home contracts/six states incomplete; dictation/send share a slot, header Stop; native motion unverified | Reuse native components and add only real capabilities. Backend-dependent functions remain explicit gaps; no fake buttons or local remote-history rewrites. |
| W-001 | Actual Home PDF export fails with dynamic ChunkLoadError | Source refresh/retry classification committed in DeepTutor `1dc8263`; no CSS cause claimed and no hosted PDF repair accepted. |
| W-002 | Quick research produces five outline topics but queue capacity is two; continuation errors while UI says completed/researching | Topic-capacity admission and terminal-state repairs committed in DeepTutor `1dc8263`; no hosted research repair accepted. |
| B-001 | Isolated build snapshot lacks Git/submodule source metadata | Prepare isolated exact source and dependency provenance; do not disable scheme generation or install stale output. |
| B-002 | Isolated resolution upgrades tokenizers from maintained 0.3.2 to 0.7.4 and fails FFI compilation | Restore the exact original resolved lock for isolated build, with locked-resolution flags and explicit dependency manifest. No root lock upgrade. |

## Committed backend increment

- Gateway: `71659b7fd435b2d4dbe64b17d5a21970ed78da64`, pushed to existing [PR #4](https://github.com/xiz2680/jonwork-server/pull/4). Final-HEAD suite: 319 passed, 0 failed, 2783 assertions; full typecheck passed.
- DeepTutor: `1dc8263c9bfdf73f5584bc0b4a5471d055087e90`, pushed to existing [PR #33](https://github.com/xiz2680/DeepTutor/pull/33). Final-HEAD affected Python: 247 passed; affected Ruff, full web TypeScript, test compilation and 11 web tests passed. Five PyMuPDF/SWIG deprecation warnings plus a teardown warning remain unresolved and unwaived.
- Both working trees remained clean after checks. Evidence: `home-dev/final-head-checks.json`, `review/backend-commit-mapping.json`, `home-dev/*-owned.diff` and `stage2-home-handoff.md` under the evidence root.
- Home1 is read-only, separately authorized from Pi, with main-issued opaque handles backed by explicit consent and hash-only persistence. Restricted adversarial validation was interrupted by a platform content restriction and remains blocked, not passed. Source review accepts only this frozen increment, not whole-task approval. This increment has not been deployed.

## Native candidate verification

The broad candidate and latest source regression logs (`ios/stage2-native-selftest-final-candidate.log` and `ios/stage2-native-selftest-final.log`) report Test Succeeded after repairs to PDF source preservation, per-route prompt/upload body assertions, unbind notifications and stale-request fixtures. Earlier compile failures and the 120/132 failed-candidate result remain recorded. These unit/integration results do not establish native end-to-end acceptance. Exact xcresult summary, final source freeze, fresh standalone simulator build and independent final review remain required.

Seven-locale extraction checked 204 keys in 44 changed app sources; the owner is rerunning checks after the latest Home favorite/pin changes. Home metadata is a native extension partitioned by verified subject/scope/workspace/generation/origin/session, rather than a server mutation or web-sync claim. New benign smoke sessions and synthetic nonprivate attachments are the final native test scope; preexisting sessions must not be deleted or taken over. Logout/revocation/relogin are requested acceptance steps, with any credential form completed by the user in-app and no secret extraction.

## Final acceptance boundaries

The [complete matrix](conversation-feature-matrix.md) distinguishes existing webpage functionality, conditional capability, native extension and interface gaps. Pi1.0 and Home1 are separate runtime identities; Home IDs cannot be sent to Pi routes. A read-only Home adapter does not establish executable research/visualize, references, document input, branches, deletion, notebook or clarification parity. Shared web/native mutation admission remains required before those capabilities can be advertised.

Every final requirement needs evidence tied to frozen source, full dirty digest (including new files), installed executable and gateway revision. Final independent review and full native revalidation are pending. API/fixture tests, source hooks and old results do not substitute for native end-to-end tests.

The independently reviewed interim diagnostic binary has executable SHA-256 `8b2da89beb87e05d0a7975d9dd03e35e53fbb4683d64886605351dbc7da0d801`. Its auth-only source and dependency provenance are in `ios/interim-auth-build-manifest.json`; its narrow Debug simulator cmark warning disposition is in `review/cmark-warning-disposition.md`. That exception does not waive final Release or device warnings.

An instrumented pre-redesign restored baseline is recorded separately in `verify/baseline-restored/inventory.md`: twelve screenshots and three recordings cover the real restored viewer, image QuickLook, sidebar, settings navigation, search keyboard, dark theme, five Dynamic Type increments and Reduce Motion settings transitions. The original unauthenticated failure recording remains distinct. Source hooks and attempts with no observed gesture effect do not prove gesture acceptance. Final redesigned-app motion, streaming, composer, VoiceOver, long-session/reconnect, logout/relogin and complete six-state acceptance remain pending. The paired iPhone 13 Pro was disconnected during inventory; no physical-device acceptance is claimed. Simulator and physical-device records remain separate.

Rollback is by reverting only focused task commits and retaining previous accepted artifacts. Logout must revoke/clear local sensitive state while preserving cloud sessions. No database rollback, account deletion, production migration or App Store action is part of this record.

Status: In Progress. This record is an execution journal, not release or full-parity approval.
