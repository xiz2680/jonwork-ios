#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
POLICY_TEST_DIR=$(mktemp -d /tmp/jonwork-sharing-policy.XXXXXX)
trap 'rm -rf "$POLICY_TEST_DIR"' EXIT
mkdir -p "$POLICY_TEST_DIR/Sources/Jonwork" "$POLICY_TEST_DIR/Tests/JonworkTests"
cp "$PROJECT_ROOT/Jonwork/Backend/Pi/PiSharingConsent.swift" "$POLICY_TEST_DIR/Sources/Jonwork/"
cp "$PROJECT_ROOT/JonworkTests/PiSharingConsentTests.swift" "$POLICY_TEST_DIR/Tests/JonworkTests/"
cat > "$POLICY_TEST_DIR/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "JonworkSharingPolicyChecks",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Jonwork"),
        .testTarget(name: "JonworkTests", dependencies: ["Jonwork"]),
    ]
)
PACKAGE
swift test --package-path "$POLICY_TEST_DIR"
