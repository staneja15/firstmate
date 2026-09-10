#!/usr/bin/env bash
# Codex SessionStart transport for the Firstmate primary.
# Reads one Codex hook payload from stdin.
# Runs the one official session-start command in the trusted hook process.
# Native session_id, rather than an already-owned process lock, distinguishes
# a new chat from repeated delivery. The composed command owns completion
# receipts and serialization; this transport only validates scope and identity.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload=$(cat 2>/dev/null || true)
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
[ "$event" = SessionStart ] || exit 0

FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
fm_is_gate_agent "$FM_ROOT" && exit 0
fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0

session_id=$(printf '%s' "$payload" | jq -er '.session_id | strings | select(test("^[A-Za-z0-9_-]{1,128}$"))' 2>/dev/null) || {
  printf '%s\n' 'CODEX_STARTUP_IDENTITY_REQUIRED: native session_id is missing or invalid; startup was not run. Follow Codex startup recovery in docs/sessionstart-nudge.md.'
  exit 0
}
exec "$SCRIPT_DIR/fm-session-start.sh" --codex-session "$session_id"
