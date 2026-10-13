#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE_MODE="${1:-all}"
CATALYST_ARCHIVE_DESTINATION='generic/platform=macOS,variant=Mac Catalyst'

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

if [[ -d .git ]] && [[ -d FlowDown.xcworkspace ]]; then
    echo "[+] found project root: $(pwd)"
else
    echo "[-] could not find project root"
    exit 1
fi

PROJECT_ROOT=$(pwd)

BUILD_NUMBER="${BUILD_NUMBER:-}"
if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
    echo "[-] BUILD_NUMBER must be a positive integer"
    exit 1
fi

CURRENT_BUILD_NUMBER=$(awk -F= '/^CURRENT_PROJECT_VERSION/ {gsub(/[^0-9]/, "", $2); print $2}' FlowDown/Configuration/Version.xcconfig)
if [[ ! "$CURRENT_BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
    echo "[-] could not read CURRENT_PROJECT_VERSION"
    exit 1
fi
if (( BUILD_NUMBER <= CURRENT_BUILD_NUMBER )); then
    echo "[-] BUILD_NUMBER must be greater than $CURRENT_BUILD_NUMBER"
    exit 1
fi

echo "[+] BUILD_NUMBER must come from the caller's persistent monotonic release counter"
echo "[+] using build number $BUILD_NUMBER"

./Resources/DevKit/scripts/scan.license.sh

if [[ -n $(git status --porcelain) ]]; then
    echo "[-] git is not clean after refreshing licenses"
    echo "[-] review and commit the release inputs before archiving"
    exit 1
fi

archive_ios() {
    XCBUILD_LABEL=archive-ios ./Resources/DevKit/scripts/run_xcodebuild.sh \
        -workspace FlowDown.xcworkspace \
        -scheme FlowDown \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$PROJECT_ROOT/.build/Jonwork.xcarchive" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive

    echo "[+] registering jonwork ios archive in xcode organizer..."
    open "$PROJECT_ROOT/.build/Jonwork.xcarchive" -g
}

archive_macos() {
    XCBUILD_LABEL=archive-macos ./Resources/DevKit/scripts/run_xcodebuild.sh \
        -workspace FlowDown.xcworkspace \
        -scheme FlowDown \
        -configuration Release \
        -destination "$CATALYST_ARCHIVE_DESTINATION" \
        -archivePath "$PROJECT_ROOT/.build/Jonwork-macOS.xcarchive" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive

    echo "[+] registering jonwork macos archive in xcode organizer..."
    open "$PROJECT_ROOT/.build/Jonwork-macOS.xcarchive" -g
}

case "$ARCHIVE_MODE" in
    all)
        archive_ios
        archive_macos
        ;;
    ios)
        archive_ios
        ;;
    macos)
        archive_macos
        ;;
    *)
        echo "[-] unknown archive mode: $ARCHIVE_MODE"
        exit 1
        ;;
esac

echo "[+] completed successfully"

osascript -e 'display notification "Jonwork has completed the archive process." with title "Build Success"'
