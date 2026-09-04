#!/usr/bin/env bash
# Print the one-line session-start instruction only for a genuine firstmate
# primary whose current harness session has not already acquired the home lock.
# Usage: fm-sessionstart-nudge.sh [--codex]
# The Codex adapter passes --codex so a managed/restricted primary runs the one
# required session-start command outside its per-command PID namespace while an
# already-unsandboxed Codex primary keeps the normal command path.
# Every silence and error path exits 0 because Claude SessionStart exit 2 blocks
# session initialization.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-operational-input.sh
. "$SCRIPT_DIR/fm-operational-input.sh"

fm_is_gate_agent "$FM_ROOT" && exit 0
fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0

lock_is_in_ancestry() {
  local lock_pid pid=$$ _
  [ -f "$STATE/.lock" ] || return 1
  IFS= read -r lock_pid < "$STATE/.lock" 2>/dev/null || return 1
  case "$lock_pid" in
    ''|*[!0-9]*|1) return 1 ;;
  esac
  kill -0 "$lock_pid" 2>/dev/null || return 1
  for _ in 1 2 3 4 5 6 7 8; do
    [ "$pid" = "$lock_pid" ] && return 0
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || return 1
  done
  return 1
}

lock_is_in_ancestry && exit 0
nudge_body="Run \`bin/fm-session-start.sh\` now, exactly once, before executing any other instructions."
case "${1:-}" in
  '') ;;
  --codex)
    nudge_body="Run \`bin/fm-session-start.sh\` now, exactly once, before executing any other instructions; in a managed/restricted Codex permission profile, make that shell tool call with \`sandbox_permissions\` set to \`require_escalated\` and a concise justification so it executes outside the per-command PID namespace, while a disabled/unrestricted profile runs it normally."
    ;;
  *) exit 0 ;;
esac
nudge=
fm_operational_input_encode session-start \
  "$nudge_body" \
  nudge || exit 0
printf '%s\n' "$nudge"
exit 0
