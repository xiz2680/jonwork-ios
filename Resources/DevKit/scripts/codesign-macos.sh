#!/bin/zsh

set -euo pipefail

# Re-sign a built macOS (Catalyst) app after an unsigned archive.
# Env:
#   CODE_SIGNING_IDENTITY (required)
#   KEYCHAIN_DB (optional)
#   ENTITLEMENTS_PATH (optional; default FlowDown/Resources/Entitlements/Entitlements-Catalyst.entitlements)
#   EMBED_PROVISION_PROFILE (optional .provisionprofile to embed)
# Usage:
#   ./codesign-macos.sh /path/to/FlowDown.app

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "[-] app bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "${CODE_SIGNING_IDENTITY:-}" ]]; then
  echo "[-] CODE_SIGNING_IDENTITY is required" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
DEFAULT_ENTITLEMENTS="${PROJECT_ROOT}/FlowDown/Resources/Entitlements/Entitlements-Catalyst.entitlements"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$DEFAULT_ENTITLEMENTS}"

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "[-] entitlements file not found: $ENTITLEMENTS_PATH" >&2
  exit 1
fi

echo "[i] using keychain at ${KEYCHAIN_DB:-<default>}"
echo "[i] entitlements: ${ENTITLEMENTS_PATH}"

if [[ -n "${EMBED_PROVISION_PROFILE:-}" && -f "${EMBED_PROVISION_PROFILE}" ]]; then
  echo "[*] embedding provision profile ${EMBED_PROVISION_PROFILE}"
  cp "${EMBED_PROVISION_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"
fi

echo "[*] stripping existing signatures and profiles"
find "$APP_PATH" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name "embedded.provisionprofile" -type f -exec rm -f {} + 2>/dev/null || true

SCANNER="${SCRIPT_DIR}/apple-resign-scan.py"
if [[ ! -f "$SCANNER" ]]; then
  echo "[-] scanner not found: $SCANNER" >&2
  exit 1
fi

FILE_CANDIDATES=()
while IFS= read -r line; do
  FILE_CANDIDATES+=("$line")
done < <(python3 "$SCANNER" "$APP_PATH")
echo "[*] found ${#FILE_CANDIDATES[@]} candidates to sign"

sign_item() {
  local item_path="$1"
  local args=(
    --force
    --timestamp
    --generate-entitlement-der
    --strip-disallowed-xattrs
    --options runtime
    --sign "$CODE_SIGNING_IDENTITY"
  )
  if [[ -n "${KEYCHAIN_DB:-}" ]]; then
    args+=(--keychain "$KEYCHAIN_DB")
  fi
  if [[ "$item_path" == *.app ]]; then
    echo "[+] signing $(basename "$item_path") with entitlements"
    args+=(--entitlements "$ENTITLEMENTS_PATH")
  else
    echo "[+] signing $(basename "$item_path")"
  fi
  xattr -cr "$item_path" || true
  /usr/bin/codesign "${args[@]}" "$item_path" || true
}

for ITEM in "${FILE_CANDIDATES[@]}"; do
  sign_item "$ITEM"
done

echo "[*] verifying..."
VERIFY_ARGS=(--verify --deep --strict)
if [[ -n "${KEYCHAIN_DB:-}" ]]; then
  VERIFY_ARGS+=(--keychain "$KEYCHAIN_DB")
fi
/usr/bin/codesign "${VERIFY_ARGS[@]}" "$APP_PATH"

echo "[+] codesign completed for ${APP_PATH}"

