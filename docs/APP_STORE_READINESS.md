# Jonwork iOS App Store preparation

Requirement: [XIZ-129](https://linear.app/xiz2680/issue/XIZ-129), under XIZ-112. Review date: October 13, 2026. Starting source: `5df95a7`. Status: **not ready for submission**.

## Source isolation

This branch renames the committed foundation into `jonwork-ios`, with application/module names `Jonwork`. It preserves the active original checkout and its uncommitted native authentication/UI changes. Integrate and independently verify that work before selecting a release candidate. Bundle IDs remain `com.jonwork.ios` and its extension IDs. Copyright, AGPL and third-party provenance remain intact. `LandingPage/` is upstream reference material, excluded from distribution.

## First review findings

| Finding | Repair or remaining gate |
| --- | --- |
| Upstream project, targets, imports and build paths | Renamed to Jonwork, including CI and Makefile |
| README points to upstream App Store/TestFlight and pricing | Replaced with actual product/release status |
| Background audio keeps agent streaming alive through sound effects | Audio background mode removed; Live Activity decoupled from sound effects |
| Support page has no contact action | Public owned issue URL, with a warning against sharing secrets |
| AI data sharing has no explicit authorization | Workspace/model-scoped consent before send/retry, draft preservation and revocation |
| Empty collected-data inventory | Account/connection/user-content inventory based on related gateway sources |
| Committed baseline disables production sign-in | Integrate and verify active development branch's pending sign-in implementation |
| Account deletion missing | Provide an actual authenticated deletion flow and retention contract; sign-out is insufficient |
| Distribution signing and acceptance unavailable | Record intended team, validated signed export, device and TestFlight evidence |

## Repeatable checks

```sh
make test-release-checks
make test-sharing-policy
make test-model-exchange
make appstore-check
make appstore-check-strict
make package-resolve
make build-ios-simulator
make test-unit
make localization-check
make archive-ios-unsigned
python3 Resources/DevKit/scripts/appstore_check.py --app BuildArtifacts/Jonwork-unsigned.xcarchive/Products/Applications/Jonwork.app
```

Local checks cover naming, bundle identity, deployment settings, privacy reasons/categories, permission localization, contact and provenance. Success means local inputs passed; outstanding release gates are always reported. Strict mode additionally fails until each gate in `docs/appstore-release.json` has verified evidence. Never mark it verified solely because compilation passed.

The optional app inspection validates generated Info.plist, app manifest and parseability of bundled SDK manifests. It does not validate signatures or certify SDK API usage. Text/symbol scans are heuristic and need manual source review.

## GitHub tools assessed

- [fastlane precheck](https://github.com/fastlane/fastlane): real App Store Connect metadata checks, including placeholders, copyright and reachable URLs. [Maintainer documentation](https://docs.fastlane.tools/actions/precheck/) states its credential requirement and scope. After owned app/access setup, run `fastlane precheck app_identifier:com.jonwork.ios include_in_app_purchases:false`. It does not validate executable behavior.
- [Wooder's required-reason API scanner](https://github.com/Wooder/ios_17_required_reason_api_scanner): reviewed read-only text and symbol scanning. The author explicitly describes the text approach as rudimentary; findings need API/reason review.
- [berkayturk/appstore-precheck](https://github.com/berkayturk/appstore-precheck): additional community semantic review assistant, not Apple's rule engine. Not installed or executed here; no pass result claimed.

## Privacy evidence

Related server source retains account email/user IDs (`accounts.ts`), scoped installation/client identity (`pi-gateway/auth.ts`), durable sessions/transcripts (`runtime.ts`/`store.ts`) and attachment records (`025_pi_gateway.sql`). This supports app-functionality declarations for Email Address, User ID, Device ID, Other User Content and selected Photos/Videos, linked to account and not used for tracking. The native password-login payload is still pending integration; the committed client does not yet implement it.

File Timestamp (`C617.1`) and User Defaults (`CA92.1`) are declared API reasons. Inspect actual release-bundled SDKs and symbols before finalizing; app declarations do not replace SDK manifests. Verify deployed providers, optional audio/file processing, retention/deletion, legal entity and App Store privacy answers.

## Required release sequence

1. Integrate and independently accept production sign-in and consent, including cancellation/retry/revocation/account changes.
2. Implement and test real account deletion. Related server exposes self-service registration; token revocation/session deletion are not substitutes.
3. Configure the owned Apple Developer team, registrations and distribution signing. None of three observed local identities is Apple Distribution; do not select another person's development identity automatically.
4. Validate signed archive/export, embedded extensions, capabilities and privacy report with Organizer/App Store Connect.
5. Publish reachable owned privacy/support URLs. The public repository policy can be linked once this branch is published; verify it before supplying metadata.
6. Complete age rating, real device screenshots, export compliance, pricing/storefronts and a working reviewer account.
7. Verify physical supported devices, VoiceOver/large text, IPv6-only network, attachments and background recovery.
8. Complete internal TestFlight from immutable source/build IDs, record compatible rollback and obtain release acceptance before App Review.

These gates remain In Progress. This branch does not submit to Apple or assert a distributed release.

The separate first-round validation recorded controlled gateway failures for token refresh/revoke, SSE expiry, controller lease renewal, JSONL writer isolation and restored tool projection. The related server was actively being modified when this branch was prepared. These are risk inputs, not a verdict on its final code. The new gateway-contract gate requires final-version independent contract and native journey evidence before submission. Debug discovery and signed physical-device validation were also blocked in that run.

## Official requirements checked

Apple's [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) require uploads since April 28, 2026 to use Xcode 26+ and iOS 26 SDK. Local Xcode is 26.3; verify the archive's actual SDK.

[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) cover background-mode purpose (2.5.4), account/data handling (5.1.1), and explicit third-party AI data-sharing permission (5.1.2(i)). [Review preparation](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review) requires working access to account features. [Privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) requires valid app/applicable SDK manifests.

## Verification results

- Project/plist/scheme/test-plan/catalog parsing and Makefile dry runs: passed.
- Release-check regressions: 7 passed.
- Final arm64 simulator build: passed through `make build-ios-simulator` with isolated cached dependencies.
- Dedicated iPhone 17 Pro simulator, iOS 26.3.1: 72 focused tests passed, then the offline application run passed 281 tests with 0 failures and 6 skipped. Live-provider E2E suites were explicitly excluded; these results do not validate the live production gateway.
- Standalone sharing-policy tests: 6 passed; renamed ModelExchange package tests: 3 passed.
- All six app/extension/widget localization catalogs: passed. All three iOS icon variants are 1024x1024 without alpha; their existing J pixels were retained and filenames renamed.
- Local App Store checks: 0 source errors. Strict mode correctly fails on 9 unverified release gates, including final compiler-warning review.
- Unsigned production Release archive: succeeded. The packaged app passed `appstore_check.py --app` with 0 local input errors; 9 release gates remain unresolved. Archive SDK: iphoneos26.2; bundle: com.jonwork.ios. This does not establish signed distribution readiness. The Makefile now forces a single Release configuration for unsigned archives, including when callers pass CONFIGURATION=Debug.
- Independent source roles are separate agents. Herdr role and physical-device/TestFlight acceptance were not obtained in this desktop chat.

The first build exposed two broken shared-source symlinks after the directory rename and one expensive Swift type-inference expression in the consent dialog. Both symlinks and the expression were fixed before the successful final build/tests. Independent review also found and verified repairs for authorization changes during uploads and stale grants after authentication failure.

The actual Wooder text scan was run against app and framework source (script SHA-256 `dfd28946b7b723577b50b6d0193b38af495f38f781cd85eec8cf400fc0ab4020`). App matches covered file timestamps; framework matches were CloudKit mock-record timestamps. Its anchored UserDefaults pattern misses normal Swift calls, so a separate targeted search confirmed 26 UserDefaults references. No binary scan or full SDK privacy certification is claimed.

Follow-up requirements are recorded as [XIZ-130](https://linear.app/xiz2680/issue/XIZ-130) (native sign-in/final gateway acceptance), [XIZ-131](https://linear.app/xiz2680/issue/XIZ-131) (account/data deletion), and [XIZ-132](https://linear.app/xiz2680/issue/XIZ-132) (signing, metadata and TestFlight). Merge this rename branch with its parent before applying outstanding development changes; do not copy the original source tree over consent fixes.

## Direct website connection follow-up

Per the user request, Debug and Release now select `https://jonwork.com` in xcconfig and runtime validation. QA and ProductionCandidate keep their separate endpoints. The earlier unsigned archive evidence belongs to the previous endpoint configuration and must be regenerated for a final candidate. On 2026-10-13, an unauthenticated GET to `https://jonwork.com/.well-known/pi-gateway` returned HTTP 307 to `/login?next=%2F.well-known%2Fpi-gateway`, rather than public discovery JSON. The native login therefore still needs deployed gateway routing on this origin. No account password was submitted and no successful login is claimed.
