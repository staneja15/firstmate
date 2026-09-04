#!/usr/bin/env bash
# Codex SessionStart transport for the Firstmate primary.
# Reads one Codex hook payload from stdin.
# Runs the one official session-start command in the trusted hook process.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload=$(cat 2>/dev/null || true)
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
[ "$event" = SessionStart ] || exit 0

nudge=$("$SCRIPT_DIR/fm-sessionstart-nudge.sh" --codex 2>/dev/null) || exit 0
[ -n "$nudge" ] || exit 0

exec "$SCRIPT_DIR/fm-session-start.sh"
