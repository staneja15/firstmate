#!/usr/bin/env bash
# Enter away mode and run the sub-supervisor daemon in a harness-tracked
# foreground process when one is not already alive.
#
# Usage: fm-afk-start.sh
#   Refuses with exit 3 and changes nothing when this home holds a standing
#   away-mode refusal (a non-empty, or unreadable, config/afk-refuse); else sets state/.afk
#   unless FM_AFK_STATE_PREPARED=1, checks state/.supervise-daemon.lock, and:
#     - prints "afk: daemon already running pid=<pid>" then exits 0 when that
#       lock is held by a live daemon (a REFRESH: no stale-artifact clear);
#     - otherwise clears any prior away session's stale escalation artifacts
#       (fm_afk_clear_stale_artifacts) for a direct, non-prepared start, then
#       execs bin/fm-supervise-daemon.sh in the foreground. A prepared start was
#       already cleared transactionally by bin/fm-afk-launch.sh.
#
# This file is sourceable: its BASH_SOURCE guard keeps main from running, while
# exposing the daemon-lock helpers and fm_afk_clear_stale_artifacts. Sourcing it
# enables nounset and errexit; callers that need different shell options must
# restore them explicitly.
#
# This is the COMMON daemon entry for every backend. HOW it becomes a tracked
# background process differs by harness/backend and is owned elsewhere:
#   - Harnesses with a native in-pane tracked-background tool (e.g. claude, grok)
#     run this directly via that tool, so the daemon inherits the captain pane's
#     env and auto-discovers it.
#   - Harnesses with NO native background mechanism (e.g. pi) run this THROUGH
#     bin/fm-afk-launch.sh, which creates a non-visible tracked terminal per
#     backend (herdr tab/workspace, tmux detached session) and passes the
#     captain pane in as FM_SUPERVISOR_TARGET so injection targets it, not the
#     daemon's own new pane.
# Do not wrap this in `nohup ... &`: Codex/herdr can reap fire-and-forget shell
# children after the tool call returns, while a tracked background terminal stays
# attached and has a real lifecycle.
set -eu

FM_AFK_START_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$FM_AFK_START_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
FM_AFK_STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
FM_AFK_CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
FM_AFK_REFUSE_FILE="$FM_AFK_CONFIG/afk-refuse"
FM_AFK_LOCK="$FM_AFK_STATE/.supervise-daemon.lock"
FM_AFK_DAEMON="$FM_AFK_START_DIR/fm-supervise-daemon.sh"

# shellcheck source=bin/fm-wake-lib.sh
. "$FM_AFK_START_DIR/fm-wake-lib.sh"

fm_afk_start_usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# STANDING AWAY-MODE REFUSAL (task away-mode-composer-guard-blind-aw3).
#
# Why this exists: on 2026-08-18 firstmate entered away mode against a standing
# captain instruction not to. The instruction was real and still in force, but it
# lived only in a backlog task body, which the /afk path never reads, so nothing
# could stop it - and the run then wedged for 59801s exactly as the instruction
# had anticipated. An instruction that only an agent's memory enforces is not
# enforced.
#
# The mechanism is deliberately the smallest thing that works: a non-empty
# config/afk-refuse in this home holds the refusal, and its non-blank lines are
# the reason, printed so whoever hits it learns WHY without hunting for the
# backlog item. Both away-mode entry paths consult it before touching any state,
# so the refusal cannot be entered around; clearing it is `rm`. It gates ENTRY
# only - never the return path - so a home can always come back out of away mode,
# and per-wake supervision is untouched either way.
#
# The printed reason is bounded at FM_AFK_REFUSE_MAX_LINES non-blank lines
# because it lands in a live pane, but a bound that dropped lines silently would
# recreate the very loss this file exists to prevent, so an over-long reason ends
# with an explicit truncation marker naming the file to read in full.
#
# Absent means no refusal, and present-but-blank means no refusal (away mode must
# never be disabled by an accident that names no reason). Present-but-UNREADABLE
# refuses: the file is there, so a refusal may well be recorded in it, and the
# only safe reading of a gate we cannot read is that it is closed.
FM_AFK_REFUSE_MAX_LINES=20

fm_afk_refusal_reason() {
  local reason total status=0
  [ -f "$FM_AFK_REFUSE_FILE" ] || return 1
  # grep exits 1 for "no non-blank lines" (deliberately NOT a refusal) but 2 for
  # an I/O or permission error on a file that IS present. Collapsing the two
  # would let an unreadable refusal file permit away-mode entry silently, which
  # is exactly backwards for a gate whose whole job is to stop it, so a file we
  # cannot read is itself a standing refusal.
  reason=$(grep -v '^[[:space:]]*$' "$FM_AFK_REFUSE_FILE" 2>/dev/null) || status=$?
  if [ "$status" -ge 2 ]; then
    printf '%s exists but could not be read (grep exit %s); away mode fails closed until it is made readable or removed\n' \
      "$FM_AFK_REFUSE_FILE" "$status"
    return 0
  fi
  [ -n "$reason" ] || return 1
  total=$(printf '%s\n' "$reason" | wc -l | tr -d '[:space:]')
  printf '%s\n' "$reason" | head -n "$FM_AFK_REFUSE_MAX_LINES"
  [ "$total" -le "$FM_AFK_REFUSE_MAX_LINES" ] || \
    printf '... (reason truncated after %s of %s lines; read %s in full)\n' \
      "$FM_AFK_REFUSE_MAX_LINES" "$total" "$FM_AFK_REFUSE_FILE"
}

# fm_afk_refuse_if_standing: return 0 when away mode may be entered; print the
# refusal loudly and return 1 when it may not.
fm_afk_refuse_if_standing() {
  local reason
  reason=$(fm_afk_refusal_reason) || return 0
  {
    printf 'afk: REFUSED - away mode is disabled in this home by %s\n' "$FM_AFK_REFUSE_FILE"
    printf '%s\n' "$reason" | sed 's/^/afk:   /'
    printf 'afk: nothing was changed. Remove that file to re-enable away mode.\n'
    printf 'afk: normal per-wake supervision is unaffected and stays available.\n'
  } >&2
  return 1
}

# fm_afk_clear_stale_artifacts: on a FRESH away-session entry (the daemon is not
# already running), drop the previous away session's leftover escalation-delivery
# artifacts so they cannot surface as stale escalations under the new session.
# These are session-scoped by timing: a fresh entry owns a new supervision
# session and the new daemon has not produced anything yet, so anything present
# here belongs to a PRIOR session. This never drops a genuinely-pending
# escalation - the delivery buffer is a transient cache, and any condition still
# true (a crew still blocked, a check still firing) is re-derived and re-escalated
# fresh by the daemon's heartbeat catch-all scan and the durable
# state/.wake-queue replay (see docs/herdr-backend.md "Away-mode stale-artifact
# lifecycle" and bin/fm-supervise-daemon.sh's escalate_add/inject_wedge_alarm).
# NOT called on a refresh (daemon already alive), so the current session's own
# buffered escalations are preserved.
fm_afk_clear_stale_artifacts() {  # <state-dir>
  local state=$1
  rm -f "$state/.subsuper-escalations" \
        "$state/.subsuper-escalations.since" \
        "$state/.subsuper-inject-wedged" 2>/dev/null
}

daemon_lock_owner() {
  local owner
  if [ -L "$FM_AFK_LOCK" ]; then
    owner=$(readlink "$FM_AFK_LOCK" 2>/dev/null) || return 1
    [ -n "$owner" ] || return 1
    case "$owner" in
      /*) printf '%s\n' "$owner" ;;
      *) printf '%s/%s\n' "$(dirname "$FM_AFK_LOCK")" "$owner" ;;
    esac
    return 0
  fi
  [ -d "$FM_AFK_LOCK" ] || return 1
  printf '%s\n' "$FM_AFK_LOCK"
}

daemon_pid_matches() {
  local pid=$1 owner=$2 identity current command
  identity=$(cat "$owner/pid-identity" 2>/dev/null || true)
  if [ -n "$identity" ]; then
    current=$(fm_pid_identity "$pid") || return 1
    [ "$current" = "$identity" ]
    return
  fi
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  case "$command" in
    *"$FM_AFK_DAEMON"*|*"fm-supervise-daemon.sh"*) return 0 ;;
  esac
  return 1
}

daemon_lock_pid() {
  local owner
  owner=$(daemon_lock_owner) || return 1
  cat "$owner/pid" 2>/dev/null || true
}

daemon_lock_held_by_live_daemon() {
  local owner pid
  owner=$(daemon_lock_owner) || return 1
  pid=$(cat "$owner/pid" 2>/dev/null || true)
  fm_pid_alive "$pid" || return 1
  daemon_pid_matches "$pid" "$owner"
}

fm_afk_start_main() {
  case "${1:-}" in
    '' ) ;;
    -h|--help) fm_afk_start_usage; return 0 ;;
    * ) echo "usage: $(basename "${BASH_SOURCE[1]:-fm-afk-start.sh}")" >&2; return 2 ;;
  esac

  # Before ANY mutation, including the state/.afk write below.
  fm_afk_refuse_if_standing || return 3

  mkdir -p "$FM_AFK_STATE"
  if [ "${FM_AFK_STATE_PREPARED:-0}" = 1 ]; then
    [ -f "$FM_AFK_STATE/.afk" ] || { echo "afk: launcher-prepared state is missing" >&2; return 1; }
  else
    date '+%s' > "$FM_AFK_STATE/.afk"
  fi

  local pid
  pid=$(daemon_lock_pid 2>/dev/null || true)
  if daemon_lock_held_by_live_daemon; then
    echo "afk: daemon already running pid=$pid"
    return 0
  fi

  if fm_pid_alive "$pid" && [ -n "$pid" ]; then
    fm_lock_remove_path "$FM_AFK_LOCK" 2>/dev/null || true
  fi

  # Fresh start: clear the previous away session's stale delivery artifacts
  # before the new daemon can surface them (fix for the leaked-artifact defect).
  if [ "${FM_AFK_STATE_PREPARED:-0}" != 1 ]; then
    fm_afk_clear_stale_artifacts "$FM_AFK_STATE"
  fi

  echo "afk: starting supervise daemon in foreground; keep this command as a tracked background session"
  exec "$FM_AFK_DAEMON"
}

# Run only when executed, not when sourced (tests source fm_afk_clear_stale_artifacts
# and the lock helpers directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  fm_afk_start_main "$@"
fi
