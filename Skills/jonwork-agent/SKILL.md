---
name: jonwork-agent
description: Use when helping contributors build, validate, or prepare the Jonwork iOS Pi client for release.
---

# Jonwork iOS Agent Skill

Use the repository documentation as the product source of truth. Jonwork is a native iOS client for Pi sessions; inherited upstream capabilities are not automatically part of its release scope.

## Resources

- Product repository: https://github.com/xiz2680/jonwork-ios
- Product support: https://github.com/xiz2680/jonwork-ios/issues
- Upstream UI provenance: https://github.com/Lakr233/FlowDown
- Development requirements: `CONTRIBUTING.md`
- Scope: `docs/PRODUCT_SCOPE.md`
- Gateway contract: `docs/PI_BACKEND_CONTRACT.md`
- Verification: `docs/QUALITY_GATES.md`

Read these files before implementing changes. Use the root Makefile for build and test workflows. Preserve upstream licenses and compatible on-disk formats. Do not advertise an App Store listing, pricing, production endpoint, or distribution status without release evidence.
