#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

WORKSPACE="${WORKSPACE:-Jonwork.xcworkspace}"
SCHEME="${SCHEME:-Jonwork}"
WORKSPACE_RESOLVED="Jonwork.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGE_RESOLVED_FILES=(
    Frameworks/*/Package.resolved
)

echo "[+] upgrading workspace packages..."
rm -f "$WORKSPACE_RESOLVED"
xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -resolvePackageDependencies \
    | xcbeautify --is-ci --disable-colored-output --disable-logging

for file in "${PACKAGE_RESOLVED_FILES[@]}"; do
    package_path="$(dirname "$file")"
    echo "[+] upgrading $package_path packages..."
    swift package --package-path "$package_path" update
done

echo "[+] completed successfully"
