#!/bin/zsh

set -euo pipefail

log() {
  echo "[notary-profile] $*"
}

fatal() {
  echo "[-] $*" >&2
  exit 1
}

ENV_FILE="${1:-}"

if [[ -z "${NOTARY_TOOLBOX_PROVISION_PROFILE_BASE64:-}" ]]; then
  fatal "NOTARY_TOOLBOX_PROVISION_PROFILE_BASE64 is required"
fi

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_DIR_XCODE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$PROFILE_DIR" "$PROFILE_DIR_XCODE"

RAW_PROFILE="$(mktemp)"
PLIST_TMP="$(mktemp)"

log "decoding provision profile"
echo "${NOTARY_TOOLBOX_PROVISION_PROFILE_BASE64}" | base64 -D > "$RAW_PROFILE"
security cms -D -i "$RAW_PROFILE" > "$PLIST_TMP"

PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$PLIST_TMP")
if [[ -z "$PROFILE_NAME" ]]; then
  rm -f "$RAW_PROFILE" "$PLIST_TMP"
  fatal "failed to read profile name"
fi

PROFILE_PATH="${PROFILE_DIR}/NotaryToolbox.provisionprofile"
cp "$RAW_PROFILE" "$PROFILE_PATH"
cp "$RAW_PROFILE" "${PROFILE_DIR_XCODE}/NotaryToolbox.provisionprofile"

rm -f "$RAW_PROFILE" "$PLIST_TMP"

log "installed profile: ${PROFILE_NAME} -> ${PROFILE_PATH}"

emit_env() {
  local key="$1"
  local value="$2"
  if [[ -n "$ENV_FILE" ]]; then
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

emit_env "PROVISIONING_PROFILE_SPECIFIER" "$PROFILE_NAME"
emit_env "NOTARY_PROVISION_PROFILE_NAME" "$PROFILE_NAME"
emit_env "NOTARY_PROVISION_PROFILE_PATH" "$PROFILE_PATH"

