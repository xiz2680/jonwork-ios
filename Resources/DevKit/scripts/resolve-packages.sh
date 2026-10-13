#!/bin/zsh

set -euo pipefail

WORKSPACE="${WORKSPACE:-Jonwork.xcworkspace}"
SCHEME="${SCHEME:-Jonwork}"

echo "[resolve-packages] workspace: $WORKSPACE"
echo "[resolve-packages] scheme: $SCHEME"

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -resolvePackageDependencies \
  | xcbeautify --is-ci --disable-colored-output --disable-logging

echo "[resolve-packages] done"

