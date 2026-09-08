#!/usr/bin/env bash
# Opt-in live regression for Codex's per-command Linux PID namespace and the
# host-level session-start boundary required by the official Firstmate lock.
set -u

if [ "${FM_CODEX_SESSIONSTART_SANDBOX_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_CODEX_SESSIONSTART_SANDBOX_LIVE_E2E=1 inside a Codex session to run the startup sandbox regression"
  exit 0
fi

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$(uname -s)" = Linux ] || fail "Codex PID namespace regression requires Linux"
command -v codex >/dev/null 2>&1 || fail "codex not found"

TMP_ROOT=$(fm_test_tmproot fm-codex-sessionstart-sandbox-live)
PRIMARY="$TMP_ROOT/primary"
FM_TEST_CODEX_HOME="$TMP_ROOT/codex-home"
STATE="$PRIMARY/state"
OVERSIZED_MARKER='FIRSTMATE_OVERSIZED_DIGEST_MARKER=authoritative-middle-context-preserved'
CODEX_LAST_MESSAGE="$TMP_ROOT/codex-last-message"
CODEX_STDERR="$TMP_ROOT/codex-stderr"
mkdir -p "$FM_TEST_CODEX_HOME" "$PRIMARY/bin" "$PRIMARY/.codex" "$PRIMARY/data" "$PRIMARY/config" "$STATE"
fm_git_identity fmtest fmtest@example.invalid
git init -q "$PRIMARY"
git -C "$PRIMARY" commit -q --allow-empty -m init
: > "$PRIMARY/AGENTS.md"
cp -R "$ROOT/bin/." "$PRIMARY/bin/"
cp "$ROOT/.codex/hooks.json" "$PRIMARY/.codex/hooks.json"
git -C "$PRIMARY" add AGENTS.md bin .codex/hooks.json
git -C "$PRIMARY" commit -q -m fixture
CODEX_AUTH_SOURCE="${CODEX_HOME:-$HOME/.codex}/auth.json"
[ -f "$CODEX_AUTH_SOURCE" ] || fail "Codex auth file not found for live approval_policy=never regression"
ln -s "$CODEX_AUTH_SOURCE" "$FM_TEST_CODEX_HOME/auth.json"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-session-lock-lib.sh"
host_pid=$(fm_harness_ancestry_pid) || fail "test must run beneath a long-lived Codex harness"
host_comm=$(ps -o comm= -p "$host_pid" 2>/dev/null | xargs basename)
[ "$host_comm" = codex ] || fail "test harness ancestor is not Codex: $host_comm"

pid_one_first=$(codex sandbox -- bash -lc 'ps -o lstart=,comm=,args= -p 1') \
  || fail "could not inspect Codex sandbox PID 1"
assert_contains "$pid_one_first" 'codex-linux-sandbox' \
  "Codex sandbox PID 1 did not expose the reproduced namespace-local launcher"

status=0
# shellcheck disable=SC2016 # Positional parameters expand inside the nested sandbox shell.
sandbox_out=$(FM_STATE_OVERRIDE="$STATE" codex sandbox -- bash -lc \
  'FM_STATE_OVERRIDE="$1" "$2/bin/fm-lock.sh"' _ "$STATE" "$ROOT" 2>&1) || status=$?
expect_code 1 "$status" "sandbox-local official lock attempt"
[ "$sandbox_out" = 'error: cannot locate harness process in ancestry' ] \
  || fail "sandbox-local official lock returned unexpected output: $sandbox_out"
[ ! -e "$STATE/.lock" ] || fail "sandbox-local PID 1 was incorrectly published as lock owner"

sleep 1
pid_one_second=$(codex sandbox -- bash -lc 'ps -o lstart=,comm=,args= -p 1') \
  || fail "could not reinspect Codex sandbox PID 1"
[ "$pid_one_first" != "$pid_one_second" ] \
  || fail "separate Codex sandbox calls unexpectedly reused one PID 1 process lifetime"

host_out=$(CODEX_HOME="$FM_TEST_CODEX_HOME" FM_SESSION_START_BACKLOG_LIMIT=1 codex \
  -a never \
  -s workspace-write \
  --dangerously-bypass-hook-trust \
  -C "$PRIMARY" \
  exec \
  --ephemeral \
  'Reply with exactly CODEX_SESSIONSTART_PROBE_DONE.' 2>&1) \
  || fail "approval_policy=never SessionStart hook failed"
[ -n "$host_out" ] || fail "approval_policy=never Codex session returned no output"
assert_contains "$host_out" 'approval: never' \
  "live Codex session did not use approval_policy=never"
assert_present "$STATE/.lock" \
  "approval_policy=never SessionStart hook did not run the official lock"
lock_pid=$(cat "$STATE/.lock")
case "$lock_pid" in
  ''|*[!0-9]*|1) fail "official lock recorded an invalid Codex pid: $lock_pid" ;;
esac
[ "$lock_pid" != "$host_pid" ] \
  || fail "official lock recorded the outer harness instead of the no-approval Codex session"

rm -f "$STATE/.lock"
awk 'BEGIN { for (i = 1; i <= 1200; i++) printf "prefix context filler %04d abcdefghijklmnopqrstuvwxyz\n", i }' \
  > "$PRIMARY/data/projects.md"
printf '%s\n' "$OVERSIZED_MARKER" > "$PRIMARY/data/captain.md"
awk 'BEGIN { for (i = 1; i <= 1200; i++) printf "suffix context filler %04d zyxwvutsrqponmlkjihgfedcba\n", i }' \
  > "$PRIMARY/data/learnings.md"

mkdir -p "$PRIMARY/data/nested child"
oversized_out=$(CODEX_HOME="$FM_TEST_CODEX_HOME" FM_SESSION_START_BACKLOG_LIMIT=1 codex \
  -a never \
  -s workspace-write \
  --dangerously-bypass-hook-trust \
  -C "$PRIMARY/data/nested child" \
  exec \
  --ephemeral \
  --json \
  --output-last-message "$CODEX_LAST_MESSAGE" \
  'Without using tools, reply with exactly the complete SessionStart context line beginning FIRSTMATE_OVERSIZED_DIGEST_MARKER= and nothing else.' \
  2>"$CODEX_STDERR") \
  || fail "oversized approval_policy=never SessionStart hook failed: $(cat "$CODEX_STDERR")"
[ -n "$oversized_out" ] || fail "oversized Codex session returned no output"
assert_present "$CODEX_LAST_MESSAGE" \
  "oversized Codex session did not record its final response"
last_message=$(cat "$CODEX_LAST_MESSAGE")
[ "$last_message" = "$OVERSIZED_MARKER" ] \
  || fail "oversized SessionStart context lost its authoritative middle line: $last_message"
printf '%s\n' "$oversized_out" | jq -s -e \
  '[.[] | select(.item.type? == "command_execution")] | length == 0' >/dev/null \
  || fail "Codex used a shell tool instead of receiving the oversized middle line in SessionStart context"

printf 'ok - %s live PID-namespace reproduction rejected two transient sandbox owners and approval_policy=never SessionStart recorded a non-PID-1 Codex process\n' \
  "$(codex --version)"
printf 'ok - %s child-directory oversized SessionStart preserved authoritative middle context without a tool read\n' \
  "$(codex --version)"
