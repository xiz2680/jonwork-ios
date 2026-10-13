# jonwork-ios

Jonwork is a native Swift/UIKit client for Pi agent conversations in a connected Jonwork workspace. It adapts the existing conversation, Markdown and editor components behind the Pi gateway boundary.

This repository is preparing for distribution. It has not been submitted to App Review. See [App Store readiness](docs/APP_STORE_READINESS.md) for verified checks and unresolved release gates. FlowDown's App Store, TestFlight, pricing and services are not Jonwork distribution channels.

## Project layout

| Path | Purpose |
| --- | --- |
| `Jonwork.xcworkspace` | Xcode entry point and local package overrides |
| `Jonwork.xcodeproj` | App, test, widget and translation targets |
| `Jonwork/` | Application, backend, UIKit, configuration and resources |
| `JonworkTests/` | Application tests |
| `JonworkTranslationProvider/`, `JonworkWidgets/` | Extensions |
| `Frameworks/` | Local packages and pinned third-party submodules |
| `Resources/DevKit/scripts/` | Build, localization, license and release tooling |
| `docs/` | Product contracts, quality gates and release records |
| `LandingPage/` | Upstream website reference; excluded from Jonwork distribution |

## Development

Use Xcode 26.x or newer and the root Makefile. Open `Jonwork.xcworkspace`; the main scheme is `Jonwork`. Bundle IDs remain in the owned `com.jonwork.ios` namespace. Product directories/modules use `Jonwork`; the repository uses `jonwork-ios`.

```sh
git submodule update --init --recursive
make install-metal-toolchain
make package-resolve
make build-ios-simulator
make test-unit
make localization-check
make test-release-checks
make appstore-check
```

Builds support isolated `DERIVED_DATA`, `TEST_DESTINATION`, `TEST_ONLY` and `XCODEBUILD_EXTRA`. Use a dedicated simulator and derived-data directory for concurrent verification.

## Release preparation

```sh
make appstore-check-strict
make archive-ios-unsigned
```

The strict check fails while required release evidence is missing. An unsigned archive is build/bundle inspection evidence only. Configure the intended Developer Team locally, validate distribution signing and complete internal TestFlight acceptance before submitting.

Do not commit credentials, provisioning profiles, signing keys, build outputs or screenshots containing user data.

Support: [Jonwork iOS issues](https://github.com/xiz2680/jonwork-ios/issues). Do not disclose passwords, tokens or private conversations in public issues.

## Source and license

Jonwork derives from [FlowDown](https://github.com/Lakr233/FlowDown). Source remains under [AGPL-3.0](LICENSE); original authorship and third-party notices are retained. Upstream name, icon and artwork are not licensed as Jonwork branding. See [provenance](docs/UPSTREAM_PROVENANCE.md).

Historical storage and model-exchange identifiers remain where changing them would lose data or break compatibility.

[简体中文](Resources/i18n/zh-Hans/README.md)
