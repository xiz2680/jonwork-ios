# Enterprise and App Store Quality Gates

## Gate 1: Requirement Ready

- Linear issue has user outcome, scope, non-goals, acceptance criteria, design evidence, dependencies, and rollback.
- Existing FlowDown reuse decision is documented.
- Pi contract change, if any, is versioned and linked.
- Privacy, entitlement, data retention, and App Store review impact are identified.

## Gate 2: Design Ready

- Happy path and loading, empty, offline, error, retry, permission, viewer, controller, abort, and released states exist.
- Dynamic Type, VoiceOver, dark mode, Reduce Motion, and increased contrast behavior are specified.
- Interaction does not depend on hidden gestures alone.
- Product review confirms the experience meets `docs/PRODUCT_SCOPE.md`.

## Gate 3: Implementation Ready

- Pi transport is isolated from UIKit behind testable protocols.
- Existing FlowDown components are reused when available.
- New state transitions have unit tests and replay fixtures.
- Errors are typed and user-facing recovery is actionable.
- No secrets, proprietary FlowDown brand assets, or user data enter source control.

## Gate 4: Continuous Integration

Required for every pull request:

- dependency resolution through `make package-resolve`;
- clean iOS build through the repository Makefile;
- app unit tests and adapter tests;
- static analysis and compiler warnings reviewed;
- localization completeness check;
- dependency license and vulnerability review;
- deterministic replay tests for streaming and tool sequences.

Warnings are failures unless a documented upstream exception is approved in Linear.

## Gate 5: Independent Review

Reviewer evidence covers:

- architecture boundary and reuse rule;
- race conditions, cancellation, reconnection, and idempotency;
- session ownership and concurrent-writer prevention;
- authentication, transport security, logging, and sensitive storage;
- accessibility and localization regressions;
- performance and memory risks in long conversations;
- migration and rollback correctness.

The reviewer must be a different Herdr role from the implementer.

## Gate 6: Independent Product Test

Run on at least the oldest supported iPhone class and a current flagship simulator/device:

1. connect and authenticate;
2. browse repositories and sessions;
3. create a conversation;
4. verify multi-turn context;
5. verify streaming text and reasoning;
6. verify tool start, update, success, error, and nested output;
7. steer and queue follow-up messages;
8. abort and resume;
9. disconnect, reconnect, and restore history;
10. switch sessions during and after activity;
11. verify viewer, takeover, and release semantics;
12. attach every supported content type;
13. exercise server, authorization, timeout, malformed-event, and version errors;
14. repeat the critical path with VoiceOver and large text;
15. validate background/foreground transitions and memory pressure.

Record device, OS, app commit, gateway commit, steps, result, logs, and screenshots in Linear.

## Gate 7: Production Candidate

- Release configuration builds from a clean checkout.
- Bundle identifier, display name, icons, launch assets, version, and build number are product-owned.
- Signing, capabilities, entitlements, privacy manifests, export compliance, and required usage descriptions are valid.
- App Privacy answers match actual code and connected services.
- Account and data deletion requirements are satisfied where applicable.
- Third-party notices are complete; FlowDown proprietary name, icon, and artwork are removed.
- Crash reporting and analytics, if enabled, have consent and redaction policies.
- Performance budgets pass on production configuration.
- TestFlight internal acceptance passes before external or App Store submission.

## Gate 8: Release and Rollback

- Release owner records immutable source and build identifiers.
- Rollout owner, time, audience, monitoring, support path, and stop conditions are defined.
- Previous accepted build and gateway compatibility are retained for rollback.
- Distributed build passes connect, create/resume, stream, tool, abort, reconnect, and release checks.
- Linear moves to Done only after distributed-build verification.

## Initial Performance Budgets

- crash-free sessions: at least 99.9% during release qualification;
- prompt-to-first-visible-update overhead added by the app: no more than 150 ms on a healthy local network;
- sustained conversation scroll: 60 fps target with no repeated multi-frame stalls;
- reconnect to authoritative state: no more than 3 seconds on a healthy network;
- no unbounded growth in message-node, Markdown, attachment, or tool-output caches;
- launch to usable session list: no more than 2 seconds after cached authentication on a supported device.

Any budget exception requires measured evidence, owner, mitigation, and expiry in Linear.
