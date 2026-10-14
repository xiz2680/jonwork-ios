# Pi iOS Product Development Standard

This repository is the iOS product shell for Pi. FlowDown remains the upstream UI and interaction foundation. Product changes must preserve its native performance and reuse existing components before new code is introduced.

## Source of Truth

Linear is the source of truth for every requirement, defect, design decision, release, and acceptance result. Work must not start from an undocumented chat request.

Each implementation issue must contain:

- problem and user outcome;
- scope and explicit non-goals;
- acceptance criteria that can be observed on a device;
- affected repository, target branch, environment, and dependencies;
- design reference or screenshots when UI is affected;
- validation commands and manual test cases;
- release target, rollback method, and App Store impact;
- links to the implementation commit or pull request and verification evidence.

Use only the existing business states that map to: Todo, In Progress, Ready to Release, and Done. Development completion is not Done. Done requires an accepted release or, for non-release work, recorded independent verification.

## Delivery Workflow

1. Product manager refines the Linear requirement and acceptance criteria.
2. A Herdr coordinator assigns explicit roles in separate agents or panes.
3. Product designer defines interaction states and visual acceptance evidence.
4. Architect defines the Pi boundary and confirms reuse versus replacement.
5. iOS developer implements and performs focused self-tests.
6. Reviewer independently audits the diff, state model, security, and regressions.
7. Tester independently validates the user journey on supported devices.
8. Release owner produces the signed candidate, checks rollback readiness, and submits only within the authorized release scope.
9. Product manager verifies the distributed build and closes the Linear issue.

The developer may not approve their own implementation. A role is recorded only after the Herdr agent has started and accepted the task. If Herdr is unavailable, work remains In Progress and the missing independent role evidence is recorded.

## Default Authorization

Routine implementation, tests, local builds, documentation, Linear updates, and reversible repository operations are pre-authorized. Do not repeatedly ask for confirmation.

Stop only when work requires credentials, certificates, paid services, destructive data changes, external communication beyond the recorded release scope, or a product decision that changes the accepted outcome.

## Product Scope

The product is a premium native iOS interface for Pi conversations. The first release includes only the conversation experience and the minimum supporting shell required to use it.

In scope:

- server connection and authentication;
- repository selection;
- create, resume, rename, switch, and release sessions;
- controller/viewer ownership and takeover;
- streaming user, assistant, reasoning, and tool messages;
- queued steering and follow-up prompts;
- model and thinking-level selection;
- abort, retry, reconnect, error recovery, and history restoration;
- text, image, and file attachments supported by Pi;
- usage/context indicators needed for confident operation;
- accessibility, localization, privacy disclosures, and App Store readiness.

Out of scope unless a Linear requirement adds it:

- generic multi-provider configuration inherited from Jonwork;
- local MLX model management;
- FlowDown-specific cloud services, branding, subscriptions, or artwork;
- features that duplicate Pi server capabilities;
- a separate chat renderer when an existing FlowDown component can be adapted.

## Reuse-First Rule

Before adding code, identify the existing FlowDown component and record one of these decisions in Linear:

1. reuse unchanged;
2. adapt behind a protocol;
3. remove because it conflicts with Pi;
4. replace only when a documented gap prevents acceptance.

New chat timelines, Markdown renderers, composers, attachment pickers, tool cards, conversation lists, and visual effects are prohibited when equivalent FlowDown implementations exist. Pi integration belongs behind a transport and event adapter, not inside views.

## Architecture Rules

- UIKit and FlowDown's existing view hierarchy remain the primary UI technology.
- Views consume product-level conversation models and never decode Pi wire events directly.
- `PiService` owns HTTP, SSE, authentication, retries, and request cancellation.
- `PiEventAdapter` converts Pi state and events into stable app-domain events.
- Session ownership, reconnect, and replay behavior must be deterministic and tested.
- Credentials belong in Keychain. Tokens, session contents, and tool output must not be logged in release builds.
- Network security uses TLS outside local development. Insecure transport exceptions are release blockers.
- Public protocols and injected dependencies are preferred over new global singletons.
- All user-visible strings use the localization system and ship in every supported locale.
- New features include accessibility labels, Dynamic Type behavior, VoiceOver order, contrast checks, and Reduce Motion handling.

## Git and Change Control

- Product branches use `codex/<linear-id>-<short-name>` unless Linear supplies an approved branch.
- This repository starts with a clean Jonwork-owned root commit and does not import FlowDown Git history. Record the source FlowDown release and license provenance in documentation; evaluate future source updates as explicit, reviewable vendor changes.
- Keep commits focused and reference the Linear identifier.
- Do not commit secrets, signing assets, derived data, screenshots, or user session data.
- Every pull request contains summary, Linear link, risk, test evidence, screenshots for UI changes, migration notes, and rollback steps.
- Generated files and dependency lock changes require explicit review in the pull request.

## Required Quality Gates

Every production change must pass the gates in `docs/QUALITY_GATES.md`. At minimum:

- package resolution and clean iOS build through the top-level Makefile;
- focused unit tests for adapters and state transitions;
- independent code review;
- device or simulator journey validation;
- accessibility and privacy review for affected surfaces;
- release build, signing, archive validation, and rollback evidence before submission.

## Definition of Done

A requirement is Done only when:

- all acceptance criteria have evidence;
- no unresolved critical or high-severity defect remains;
- independent review and test roles have approved it;
- the release candidate is traceable to source and Linear;
- required App Store metadata, privacy declarations, entitlements, and signing are valid;
- the distributed build has passed the same critical user journey;
- release and rollback records are attached to Linear.
