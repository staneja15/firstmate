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
HOME_DIR="$TMP_ROOT/home"
STATE="$HOME_DIR/state"
mkdir -p "$STATE"

# shellcheck source=bin/fm-session-lock-lib.sh
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

host_out=$(FM_STATE_OVERRIDE="$STATE" "$ROOT/bin/fm-lock.sh") \
  || fail "host-level official lock attempt failed"
[ "$host_out" = "lock acquired: harness pid $host_pid" ] \
  || fail "host-level official lock returned unexpected output: $host_out"
[ "$(cat "$STATE/.lock")" = "$host_pid" ] \
  || fail "official lock did not record the long-lived host Codex pid"

printf 'ok - %s live PID-namespace reproduction rejected two transient sandbox owners and the host boundary recorded Codex pid %s\n' \
  "$(codex --version)" "$host_pid"
