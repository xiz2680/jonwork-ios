#!/bin/zsh

set -euo pipefail

# Shared wrapper for build and test entrypoints.
# It treats the log content as the source of truth so `make` stops on real
# compiler or test failures even when `xcodebuild` exits successfully.

LABEL="${XCBUILD_LABEL:-xcodebuild}"
RAW_LOG=$(mktemp -t "jonwork-${LABEL//\//_}.raw.XXXXXX.log")
LOG=$(mktemp -t "jonwork-${LABEL//\//_}.XXXXXX.log")
ERROR_LOG=$(mktemp -t "jonwork-${LABEL//\//_}.errors.XXXXXX.log")
FILTER_RE='Metal\.xctoolchain/usr/lib/swift/maccatalyst|CoreData: error: Failed to create NSXPCConnection'
trap 'rm -f "$RAW_LOG" "$LOG" "$ERROR_LOG"' EXIT

capture_direct() {
    if xcodebuild "$@" >"$RAW_LOG" 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

capture_with_pty() {
    if script -q "$RAW_LOG" xcodebuild "$@" >/dev/null 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

normalize_log() {
    perl -ne '
        s/\r/\n/g;
        s/\x08//g;
        s/\x04//g;
        next if m{Metal\.xctoolchain/usr/lib/swift/maccatalyst};
        next if m{CoreData: error: Failed to create NSXPCConnection};
        print;
    ' "$RAW_LOG" >"$LOG"
}

capture_direct "$@"
normalize_log

if [ "${XCBUILD_FORCE_PTY:-0}" = "1" ] || grep -F "is not a workspace file" "$LOG" >/dev/null 2>&1; then
    capture_with_pty "$@"
    normalize_log
fi

replay_log() {
    if command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify --disable-colored-output --disable-logging <"$LOG" | grep -Ev "$FILTER_RE" || true
    else
        grep -Ev "$FILTER_RE" "$LOG" || true
    fi
}

replay_log

ERR_RE='(^|[[:space:]])error:|^\*\* (BUILD|TEST|ARCHIVE|CLEAN|ANALYZE) FAILED \*\*|^Testing failed:|^Failing tests:|(^|[[:space:]])Assertion failed|Test crashed with signal|(^|[[:space:]])Test .* recorded an issue'

# Only the four observed, fully structured null process-assertion diagnostics are classified.
# They remain in the replayed/raw log and the numbered inventory below.
RUNTIME_NULL_RE="^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}[+-][0-9]{4} Jonwork\[[0-9]+:[0-9]+\] \[ProcessSuspension\] 0x[0-9a-fA-F]+ - ProcessAssertion::acquireSync Failed to acquire RBS assertion '(XPCConnectionTerminationWatchdog|WebProcess NearSuspended Assertion|NetworkProcess Background Assertion|WebProcess Background Assertion)' for process with PID=[0-9]+, error: \(null\)$"

FOUND_ERRORS=0
if grep -E "$ERR_RE" "$LOG" | grep -Ev "$RUNTIME_NULL_RE" >"$ERROR_LOG"; then
    FOUND_ERRORS=1
fi

RUNTIME_NULL_COUNT=$(grep -Ec "$RUNTIME_NULL_RE" "$LOG" || true)
if [ "$RUNTIME_NULL_COUNT" -gt 0 ]; then
    echo "[+] [$LABEL] classified $RUNTIME_NULL_COUNT exact null WebKit process-assertion diagnostics"
    grep -En "$RUNTIME_NULL_RE" "$LOG"
fi

if [ "$XC_STATUS" -ne 0 ] || [ "$FOUND_ERRORS" -ne 0 ]; then
    echo "" >&2
    echo "[-] [$LABEL] xcodebuild failed (exit=$XC_STATUS, errors_in_log=$FOUND_ERRORS)" >&2
    if [ "$FOUND_ERRORS" -ne 0 ]; then
        echo "---- first 40 error lines from log ----" >&2
        head -40 "$ERROR_LOG" >&2
        echo "---------------------------------------" >&2
    fi
    if [ "$XC_STATUS" -ne 0 ]; then
        echo "---- last 80 lines from log ----" >&2
        tail -80 "$LOG" >&2 || true
        echo "--------------------------------" >&2
    fi
    if [ "$XC_STATUS" -ne 0 ]; then
        exit "$XC_STATUS"
    fi
    exit 1
fi
