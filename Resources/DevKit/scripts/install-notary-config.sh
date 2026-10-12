#!/bin/zsh

set -euo pipefail

log() {
  echo "[notary-config] $*"
}

fatal() {
  echo "[-] $*" >&2
  exit 1
}

REQUIRED_VARS=(
  NOTARY_PROVISION_PROFILE_NAME
  PROVISIONING_PROFILE_SPECIFIER
  CODE_SIGNING_IDENTITY
  CODE_SIGNING_TEAM
  KEYCHAIN_DB
  NOTARIZE_KEYCHAIN_PROFILE
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${(P)var:-}" ]]; then
    fatal "${var} is required to install notary config"
  fi
done

PROFILE_NAME="$NOTARY_PROVISION_PROFILE_NAME"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
CONFIG_PATH="${PROJECT_ROOT}/FlowDown/Configuration/Developer.xcconfig"

log "profile name: ${PROFILE_NAME}"
log "profile specifier: ${PROVISIONING_PROFILE_SPECIFIER}"
log "codesign identity: ${CODE_SIGNING_IDENTITY}"
log "codesign team: ${CODE_SIGNING_TEAM}"
log "keychain db: ${KEYCHAIN_DB}"
log "notary keychain profile: ${NOTARIZE_KEYCHAIN_PROFILE}"

mkdir -p "$(dirname "$CONFIG_PATH")"
cat > "$CONFIG_PATH" <<EOF
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = ${CODE_SIGNING_TEAM}
CODE_SIGN_IDENTITY = ${CODE_SIGNING_IDENTITY}
PROVISIONING_PROFILE_SPECIFIER = ${PROVISIONING_PROFILE_SPECIFIER}
EOF

log "generated Developer.xcconfig at ${CONFIG_PATH}"

