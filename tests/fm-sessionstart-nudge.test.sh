#!/usr/bin/env bash
# Behavior and tracked-registration tests for the native session-start nudge.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

unset NO_MISTAKES_GATE

TMP_ROOT=$(fm_test_tmproot fm-sessionstart-nudge)
NUDGE="$ROOT/bin/fm-sessionstart-nudge.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-operational-input.sh"
NUDGE_TEXT="Run \`bin/fm-session-start.sh\` now, exactly once, before executing any other instructions."
CODEX_NUDGE_TEXT="Run \`bin/fm-session-start.sh\` now, exactly once, before executing any other instructions; in a managed/restricted Codex permission profile, make that shell tool call with \`sandbox_permissions\` set to \`require_escalated\` and a concise justification so it executes outside the per-command PID namespace, while a disabled/unrestricted profile runs it normally."
fm_operational_input_encode session-start "$NUDGE_TEXT" NUDGE_LINE \
  || fail "could not construct expected session-start nudge"
fm_operational_input_encode session-start "$CODEX_NUDGE_TEXT" CODEX_NUDGE_LINE \
  || fail "could not construct expected Codex session-start nudge"
fm_git_identity fmtest fmtest@example.invalid

make_primary() {
  local dir=$1
  mkdir -p "$dir/bin" "$dir/state"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
}

install_nudge_fixture() {
  local root=$1
  make_primary "$root"
  cp "$ROOT/bin/fm-codex-sessionstart-hook.sh" "$ROOT/bin/fm-sessionstart-nudge.sh" \
    "$ROOT/bin/fm-primary-scope-lib.sh" \
    "$ROOT/bin/fm-gate-refuse-lib.sh" "$ROOT/bin/fm-operational-input.sh" "$root/bin/"
  chmod +x "$root/bin/fm-codex-sessionstart-hook.sh" "$root/bin/fm-sessionstart-nudge.sh"
}

install_codex_hook_fixture() {
  local root=$1
  install_nudge_fixture "$root"
  mkdir -p "$root/.codex"
  cp "$ROOT/.codex/hooks.json" "$root/.codex/hooks.json"
  cat > "$root/bin/fm-session-start.sh" <<'SH'
#!/usr/bin/env bash
printf 'host session start\n'
printf 'ran\n' > "$FM_HOME/session-start-ran"
SH
  chmod +x "$root/bin/fm-session-start.sh"
}

run_codex_hook() {
  local root=$1 permission_mode=$2 command payload cwd=${3:-$1}
  command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$root/.codex/hooks.json")
  payload=$(jq -cn --arg mode "$permission_mode" \
    '{hook_event_name:"SessionStart",source:"startup",permission_mode:$mode}')
  (cd "$cwd" && printf '%s' "$payload" | FM_HOME="$root" bash -c "$command")
}

run_nudge() {
  local root=$1
  shift
  FM_GATE_REFUSE_BYPASS=0 FM_ROOT_OVERRIDE="$root" FM_HOME="$root" "$NUDGE" "$@"
}

expect_silent_zero() {
  local label=$1
  shift
  local out status=0
  out=$("$@" 2>&1) || status=$?
  expect_code 0 "$status" "$label must exit 0"
  [ -z "$out" ] || fail "$label must be silent, got: $out"
}

test_genuine_primary_nudges() {
  local root="$TMP_ROOT/primary" out prefix_hex status=0
  make_primary "$root"
  out=$(run_nudge "$root") || status=$?
  expect_code 0 "$status" "genuine primary nudge"
  [ "$out" = "$NUDGE_LINE" ] || fail "genuine primary printed unexpected output: $out"
  prefix_hex=$(printf '%s' "$out" | head -c 3 | od -An -tx1 | tr -d ' \n')
  [ "$prefix_hex" = e281a3 ] || fail "genuine primary nudge lost its U+2063 operational marker: $prefix_hex"
  pass "fm-sessionstart-nudge: a genuine primary gets one explicitly marked instruction line"
}

test_codex_primary_nudges_outside_managed_pid_namespace() {
  local root="$TMP_ROOT/codex-primary" out prefix_hex status=0
  make_primary "$root"
  out=$(run_nudge "$root" --codex) || status=$?
  expect_code 0 "$status" "Codex primary nudge"
  [ "$out" = "$CODEX_NUDGE_LINE" ] || fail "Codex primary printed unexpected output: $out"
  prefix_hex=$(printf '%s' "$out" | head -c 3 | od -An -tx1 | tr -d ' \n')
  [ "$prefix_hex" = e281a3 ] || fail "Codex primary nudge lost its U+2063 operational marker: $prefix_hex"
  # shellcheck disable=SC2016 # Backticks are literal prompt markup.
  assert_contains "$out" 'sandbox_permissions` set to `require_escalated' \
    "Codex primary nudge does not require the managed shell call to leave the PID namespace"
  assert_contains "$out" 'disabled/unrestricted profile runs it normally' \
    "Codex primary nudge changed the already-unsandboxed command path"
  pass "fm-sessionstart-nudge: Codex gets the exact marked host-boundary instruction"
}

test_gate_env_is_silent() {
  local root="$TMP_ROOT/gate-env"
  make_primary "$root"
  expect_silent_zero "gate env nudge" env NO_MISTAKES_GATE=1 FM_GATE_REFUSE_BYPASS=0 \
    FM_ROOT_OVERRIDE="$root" FM_HOME="$root" "$NUDGE"
  pass "fm-sessionstart-nudge: NO_MISTAKES_GATE is silent"
}

test_gate_common_dir_is_silent() {
  local source="$TMP_ROOT/gate-source" bare="$TMP_ROOT/.no-mistakes/repos/gate.git"
  local root="$TMP_ROOT/gate-worktree"
  fm_git_init_commit "$source"
  mkdir -p "$(dirname "$bare")"
  git clone --quiet --bare "$source" "$bare"
  git --git-dir="$bare" worktree add --quiet -b gate-test "$root" HEAD
  mkdir -p "$root/bin" "$root/state"
  : > "$root/AGENTS.md"
  printf 'gate-test\n' > "$root/.fm-secondmate-home"
  expect_silent_zero "gate common-dir nudge" env FM_GATE_REFUSE_BYPASS=0 \
    FM_ROOT_OVERRIDE="$root" FM_HOME="$root" "$NUDGE"
  pass "fm-sessionstart-nudge: .no-mistakes gate common-dir is silent"
}

test_unmarked_linked_worktree_is_silent() {
  local base="$TMP_ROOT/worktree-base" root="$TMP_ROOT/worktree-child"
  fm_git_worktree "$base" "$root" fm/sessionstart-linked
  mkdir -p "$root/bin" "$root/state"
  : > "$root/AGENTS.md"
  expect_silent_zero "linked worktree nudge" run_nudge "$root"
  pass "fm-sessionstart-nudge: an unmarked linked task worktree is silent"
}

test_linked_secondmate_primary_nudges() {
  local base="$TMP_ROOT/secondmate-base" root="$TMP_ROOT/secondmate-home" out status=0
  fm_git_worktree "$base" "$root" fm/sessionstart-secondmate
  mkdir -p "$root/bin" "$root/state"
  : > "$root/AGENTS.md"
  printf 'sessionstart-sm\n' > "$root/.fm-secondmate-home"
  out=$(run_nudge "$root") || status=$?
  expect_code 0 "$status" "linked secondmate nudge"
  [ "$out" = "$NUDGE_LINE" ] || fail "linked secondmate printed unexpected output: $out"
  pass "fm-sessionstart-nudge: a marked linked secondmate home is a primary"
}

test_missing_state_is_silent() {
  local root="$TMP_ROOT/missing-state"
  make_primary "$root"
  rmdir "$root/state"
  expect_silent_zero "missing state nudge" run_nudge "$root"
  pass "fm-sessionstart-nudge: a checkout without state is silent"
}

test_owned_lock_is_silent() {
  local root="$TMP_ROOT/already-ran"
  make_primary "$root"
  printf '%s\n' "$$" > "$root/state/.lock"
  expect_silent_zero "owned lock nudge" run_nudge "$root"
  expect_silent_zero "owned Codex lock nudge" run_nudge "$root" --codex
  pass "fm-sessionstart-nudge: a lock holder in process ancestry silences both output variants"
}

test_codex_default_hook_runs_session_start_on_host() {
  local root="$TMP_ROOT/codex-default-primary" out status=0
  install_codex_hook_fixture "$root"
  out=$(run_codex_hook "$root" default) || status=$?
  expect_code 0 "$status" "Codex default host session start"
  [ "$out" = 'host session start' ] || fail "Codex default hook printed unexpected output: $out"
  assert_grep 'ran' "$root/session-start-ran" \
    "Codex default hook did not invoke the official session-start path"
  pass "Codex default SessionStart invokes session start in the trusted hook"
}

test_codex_dontask_hook_runs_session_start_on_host() {
  local root="$TMP_ROOT/codex-dontask-primary" out status=0
  install_codex_hook_fixture "$root"
  out=$(run_codex_hook "$root" dontAsk) || status=$?
  expect_code 0 "$status" "Codex dontAsk host session start"
  [ "$out" = 'host session start' ] || fail "Codex dontAsk hook printed unexpected output: $out"
  assert_grep 'ran' "$root/session-start-ran" \
    "Codex dontAsk hook did not invoke the official session-start path"
  pass "Codex dontAsk SessionStart invokes session start in the trusted hook"
}

test_codex_unrestricted_hook_runs_normal_session_start() {
  local root="$TMP_ROOT/codex-unrestricted-primary" out status=0
  install_codex_hook_fixture "$root"
  out=$(run_codex_hook "$root" bypassPermissions) || status=$?
  expect_code 0 "$status" "Codex unrestricted host session start"
  [ "$out" = 'host session start' ] || fail "Codex unrestricted hook printed unexpected output: $out"
  assert_grep 'ran' "$root/session-start-ran" \
    "Codex unrestricted hook did not invoke the normal session-start path"
  pass "Codex unrestricted SessionStart preserves the normal startup command"
}

test_codex_dontask_hook_preserves_owned_lock_silence() {
  local root="$TMP_ROOT/codex-dontask-owned" out status=0
  install_codex_hook_fixture "$root"
  printf '%s\n' "$$" > "$root/state/.lock"
  out=$(run_codex_hook "$root" dontAsk) || status=$?
  expect_code 0 "$status" "Codex dontAsk owned-lock hook"
  [ -z "$out" ] || fail "Codex dontAsk owned-lock hook printed output: $out"
  assert_absent "$root/session-start-ran" \
    "Codex dontAsk hook reran session start after verified lock ownership"
  pass "Codex dontAsk SessionStart preserves already-owned-lock silence"
}

test_codex_child_directory_resolves_owning_root() {
  local root="$TMP_ROOT/codex child primary" child mode out status
  install_codex_hook_fixture "$root"
  child="$root/data/nested child"
  mkdir -p "$child"
  for mode in default dontAsk bypassPermissions; do
    status=0
    rm -f "$root/session-start-ran"
    out=$(run_codex_hook "$root" "$mode" "$child") || status=$?
    expect_code 0 "$status" "Codex $mode child-directory startup"
    [ "$out" = 'host session start' ] || fail "Codex child hook lost startup output: $out"
    assert_grep 'ran' "$root/session-start-ran" "Codex child hook skipped official startup"
  done
  pass "Codex child-directory SessionStart resolves the owning Git root in every permission mode"

  rm -f "$root/session-start-ran"
  printf '%s\n' "$$" > "$root/state/.lock"
  expect_silent_zero "Codex child owned-lock hook" run_codex_hook "$root" dontAsk "$child"
  assert_absent "$root/session-start-ran" "Codex child hook reran owned startup"
  pass "Codex child-directory SessionStart preserves already-owned-lock silence"

  rm -f "$root/state/.lock"
  git init -q "$child"
  expect_silent_zero "Codex nested unrelated repository" run_codex_hook "$root" dontAsk "$child"
  assert_absent "$root/session-start-ran" "Codex hook crossed a nested repository boundary"
  expect_silent_zero "Codex outside repository" run_codex_hook "$root" dontAsk "$TMP_ROOT"
  assert_absent "$root/session-start-ran" "Codex hook ran outside a repository"
  pass "Codex root discovery refuses unrelated nested repositories and non-repository directories"
}

test_opencode_plugin_delivers_exact_nudge_once() {
  local root="$TMP_ROOT/opencode-primary" out status=0
  install_nudge_fixture "$root"
  out=$(PLUGIN="$ROOT/.opencode/plugins/fm-primary-sessionstart-nudge.js" \
    WORKTREE="$root" EXPECTED="$NUDGE_LINE" node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const prompts = [];
const client = {
  session: {
    promptAsync: async (request) => {
      prompts.push(request.body.parts[0].text);
    },
  },
};
const mod = await import(pathToFileURL(process.env.PLUGIN).href);
const hooks = await mod.FmPrimarySessionstartNudge({
  client,
  directory: process.env.WORKTREE,
  worktree: process.env.WORKTREE,
});
const event = {
  type: "session.created",
  properties: { sessionID: "session-nudge-test", info: { id: "session-nudge-test" } },
};
await hooks.event({ event });
await hooks.event({ event });
if (prompts.length !== 1) throw new Error(`expected one prompt, got ${prompts.length}`);
if (prompts[0] !== process.env.EXPECTED) throw new Error(`unexpected prompt: ${prompts[0]}`);
EOF
  ) || status=$?
  expect_code 0 "$status" "OpenCode exact nudge delivery"
  [ -z "$out" ] || fail "OpenCode exact nudge delivery printed output: $out"
  pass "OpenCode session.created delivers the exact wrapper nudge once per session"
}

test_claude_hook_delivers_exact_non_codex_nudge() {
  local root="$TMP_ROOT/claude-primary" command out prefix_hex status=0
  install_nudge_fixture "$root"
  command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$ROOT/.claude/settings.json")
  out=$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' \
    | CLAUDE_PROJECT_DIR="$root" bash -c "$command") || status=$?
  expect_code 0 "$status" "Claude hook exact nudge delivery"
  [ "$out" = "$NUDGE_LINE" ] || fail "Claude hook printed unexpected output: $out"
  prefix_hex=$(printf '%s' "$out" | head -c 3 | od -An -tx1 | tr -d ' \n')
  [ "$prefix_hex" = e281a3 ] || fail "Claude hook output lost its U+2063 operational marker: $prefix_hex"
  pass "Claude SessionStart hook delivers the exact marked non-Codex nudge"
}

test_grok_hook_delivers_exact_non_codex_nudge() {
  local root="$TMP_ROOT/grok-primary" command out prefix_hex status=0
  install_nudge_fixture "$root"
  command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' \
    "$ROOT/.grok/hooks/fm-primary-sessionstart-nudge.json")
  out=$(GROK_WORKSPACE_ROOT="$root" bash -c "$command") || status=$?
  expect_code 0 "$status" "Grok hook exact nudge delivery"
  [ "$out" = "$NUDGE_LINE" ] || fail "Grok hook printed unexpected output: $out"
  prefix_hex=$(printf '%s' "$out" | head -c 3 | od -An -tx1 | tr -d ' \n')
  [ "$prefix_hex" = e281a3 ] || fail "Grok hook output lost its U+2063 operational marker: $prefix_hex"
  pass "Grok SessionStart hook delivers the exact marked non-Codex nudge"
}

test_pi_transport_delivers_exact_non_codex_nudge() {
  local root="$TMP_ROOT/pi-primary" plugin out status=0
  install_nudge_fixture "$root"
  mkdir -p "$root/.pi/extensions/lib"
  plugin="$root/.pi/extensions/fm-primary-turnend-guard.ts"
  cp "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" "$plugin"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$root/.pi/extensions/lib/"
  out=$(PLUGIN="$plugin" FM_HOME="$root" EXPECTED="$NUDGE_LINE" \
    node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const handlers = new Map();
const messages = [];
const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  sendMessage(message) {
    messages.push(message);
  },
};
const mod = await import(pathToFileURL(process.env.PLUGIN).href);
mod.default(pi);
const sessionStart = handlers.get("session_start");
if (!sessionStart) throw new Error("session_start handler was not registered");
await sessionStart({ reason: "startup" });
if (messages.length !== 1) throw new Error(`expected one message, got ${messages.length}`);
const message = messages[0];
if (message.content !== process.env.EXPECTED) throw new Error(`unexpected message: ${message.content}`);
if (!message.content.startsWith("\u2063")) throw new Error("message lost its U+2063 operational marker");
if (message.customType !== "firstmate-sessionstart-nudge") throw new Error(`unexpected custom type: ${message.customType}`);
if (message.display !== false) throw new Error("session-start message must remain hidden context");
if (message.details?.kind !== "session-start") throw new Error(`unexpected message kind: ${message.details?.kind}`);
EOF
  ) || status=$?
  expect_code 0 "$status" "Pi exact nudge delivery"
  [ -z "$out" ] || fail "Pi exact nudge delivery printed output: $out"
  pass "Pi session_start transport delivers the exact marked non-Codex nudge"
}

test_claude_sessionstart_registration() {
  jq -e '.hooks.SessionStart | length == 1' "$ROOT/.claude/settings.json" >/dev/null \
    || fail "Claude SessionStart hook is not registered exactly once"
  jq -e '.hooks.SessionStart[0].matcher == "startup|resume|clear"' "$ROOT/.claude/settings.json" >/dev/null \
    || fail "Claude SessionStart matcher must include startup/resume/clear and exclude compact"
  pass "Claude registers one SessionStart hook for startup, resume, and clear"
}

test_genuine_primary_nudges
test_codex_primary_nudges_outside_managed_pid_namespace
test_gate_env_is_silent
test_gate_common_dir_is_silent
test_unmarked_linked_worktree_is_silent
test_linked_secondmate_primary_nudges
test_missing_state_is_silent
test_owned_lock_is_silent
test_codex_default_hook_runs_session_start_on_host
test_codex_dontask_hook_runs_session_start_on_host
test_codex_unrestricted_hook_runs_normal_session_start
test_codex_dontask_hook_preserves_owned_lock_silence
test_codex_child_directory_resolves_owning_root
test_opencode_plugin_delivers_exact_nudge_once
test_claude_hook_delivers_exact_non_codex_nudge
test_grok_hook_delivers_exact_non_codex_nudge
test_pi_transport_delivers_exact_non_codex_nudge
test_claude_sessionstart_registration
