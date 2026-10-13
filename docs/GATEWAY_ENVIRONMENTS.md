# iOS Gateway Environments

Jonwork selects its Gateway at build time. There is no runtime server-address field, and a saved profile from another environment is not accepted for automatic connection.

| Xcode configuration | Deployment label | Gateway |
|---|---|---|
| `Debug` | `debug` | `https://debug.agent.jonwork.com` |
| `QA` | `qa` | `https://qa.agent.jonwork.com` |
| `ProductionCandidate` | `production-candidate` | `https://candidate.agent.jonwork.com` |
| `Release` | `production` | `https://agent.jonwork.com` |

The environment and URL are supplied by the checked-in xcconfig files and embedded in the app Info.plist. Runtime validation requires HTTPS and an exact environment-to-domain match. These files contain no OAuth client secret, bearer token, model credential, or signing credential.

## Reproduce a fresh candidate install

Use a booted simulator. The uninstall step intentionally clears the app container. iOS may retain Keychain items after uninstall, but Gateway selection does not read a credential without a matching current-environment profile, so residual credentials cannot change the selected domain.

```sh
cd /Users/a/xz-workspace/jonwork2.0/FlowDown
make build-ios-simulator CONFIGURATION=ProductionCandidate DERIVED_DATA=/private/tmp/jonwork-candidate-deriveddata
plutil -p /private/tmp/jonwork-candidate-deriveddata/Build/Products/ProductionCandidate-iphonesimulator/FlowDown.app/Info.plist | grep JonworkGateway
xcrun simctl uninstall booted com.jonwork.ios || true
xcrun simctl install booted /private/tmp/jonwork-candidate-deriveddata/Build/Products/ProductionCandidate-iphonesimulator/FlowDown.app
xcrun simctl launch booted com.jonwork.ios
```

The plist inspection must show `production-candidate` and `https://candidate.agent.jonwork.com`. Opening Jonwork Workspace and choosing Sign In must use that endpoint without asking for a server address.

To verify production isolation, build to a separate derived-data directory and inspect its embedded configuration:

```sh
make build-ios-simulator CONFIGURATION=Release DERIVED_DATA=/private/tmp/jonwork-production-deriveddata
plutil -p /private/tmp/jonwork-production-deriveddata/Build/Products/Release-iphonesimulator/FlowDown.app/Info.plist | grep JonworkGateway
```

The production plist must show `production` and `https://agent.jonwork.com`; it must not contain the candidate hostname.
