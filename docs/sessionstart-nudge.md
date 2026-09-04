# Native session-start nudge

AGENTS.md section 3 is the authoritative behavioral contract for session start.
The tracked native adapters inject one instruction and never run the digest, acquire the lock, perform bootstrap work, drain notifications, or arm supervision themselves, except for the Codex path described below.
Every nudge payload starts with U+2063 and the stable `FIRSTMATE_OP: ` label and carries the current `session-start` protocol kind.
The non-Codex payload retains exactly ``Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.`` as its body.
The Codex wrapper variant preserves the one-command rule and describes the shell boundary, while its native hook consumes that output as a scope and idempotence check rather than injecting it.
The Ahoy skill owns the rule that this marked operational input is never a captain-authored session boundary, including its narrow legacy compatibility cases.

## Shared wrapper and safety

`bin/fm-sessionstart-nudge.sh` is the shared scope and idempotence guard every harness transport invokes.
The Codex adapter reaches it through `bin/fm-codex-sessionstart-hook.sh`, while every other adapter invokes it directly with no argument and retains the original output byte-for-byte.
It sources `bin/fm-gate-refuse-lib.sh` and stays silent for a no-mistakes gate agent identified by `NO_MISTAKES_GATE` or a `.no-mistakes/repos/*.git` git-common-dir.
It shares `bin/fm-primary-scope-lib.sh` with `bin/fm-turnend-guard.sh`, so the hooks use one primary-detection owner.
The Shared Predicate section of [`turnend-guard.md`](turnend-guard.md#shared-predicate) owns marker validation, plain-checkout detection, and required Firstmate-shaped paths.

Before printing, the wrapper reads `state/.lock` and walks at most eight parents from its own pid, matching `bin/fm-lock.sh` and Pi's `lockOwnership()` ancestry depth.
If the lock names a live pid in that ancestry, session start already ran in this harness session and the wrapper stays silent.
Every path exits 0, including malformed state and adapter errors, because a Claude SessionStart exit 2 blocks session initialization.

Codex can execute ordinary shell tool calls inside a per-command PID namespace whose local PID 1 is the transient `codex-linux-sandbox` launcher.
In that mode the official lock cannot see the long-lived host Codex ancestor.
The native payload does not expose a reliable distinction between `approval_policy=never` and every interactive restricted profile.
The trusted Codex hook therefore runs the one official `bin/fm-session-start.sh` invocation directly and returns its digest as developer context for every Codex permission mode.
The hook first requires a non-empty result from the shared nudge wrapper, preserving primary scope, no-mistakes gate refusal, and already-owned-lock silence before any startup mutation.
The unchanged official lock then verifies and records the host Codex process.
This boundary is scoped to the official startup command and does not provide general host command execution.
An unrestricted `bypassPermissions` session runs the same official command and unchanged lock path it used before, while restricted sessions no longer depend on a sandbox approval request.

## Harness transports

| Harness | Tracked transport | Current compatibility |
| --- | --- | --- |
| Claude | `.claude/settings.json` registers `SessionStart` for `startup`, `resume`, and `clear`, excludes `compact`, and invokes the wrapper through `CLAUDE_PROJECT_DIR`. | Native stdout context injection is supported. |
| Codex | `.codex/hooks.json` anchors to the hook process working directory, verifies a Firstmate-shaped hook-bearing root, and executes `bin/fm-codex-sessionstart-hook.sh`. | Every permission mode executes the one official startup command in the trusted host hook; `bypassPermissions` retains the same normal command and lock path. |
| OpenCode | `.opencode/plugins/fm-primary-sessionstart-nudge.js` listens for `session.created`, runs once per session id, and calls `client.session.promptAsync` only when the wrapper prints a nudge. | Interactive TUI delivery is supported; headless `opencode run` is intentionally fail-open because the process can exit before the queued turn. |
| Pi | `.pi/extensions/fm-primary-turnend-guard.ts` handles `session_start` reasons `startup`, `new`, and `resume`, then injects the wrapper output with `pi.sendMessage`. | The custom message reaches model context without racing an initial positional prompt. |
| Grok | `.grok/hooks/fm-primary-sessionstart-nudge.json` registers a project `SessionStart` hook and invokes the wrapper through inline-defaulted `${GROK_WORKSPACE_ROOT:-}`. | The project hook runs when the checkout is trusted, but Grok currently discards hook stdout from model context, so this path is intentionally fail-open. |

The OpenCode nudge runs only on `session.created`.
The watcher-arm and turn-end plugins run later on `session.idle`, and the guard lets the watcher coordinator act first, so the plugins do not race for one lifecycle event.

Grok's guaranteed-loading alternative is a global token-guarded hook like the pattern used by `bin/fm-spawn.sh`.
That alternative expands trust and writes outside this repository, so Firstmate never installs it or grants folder trust automatically.

## Regression coverage

`tests/fm-sessionstart-nudge.test.sh` proves wrapper silence for both gate signals, an unmarked linked worktree, a missing state directory, and an already-owned lock.
It proves the exact original U+2063 `FIRSTMATE_OP:`-prefixed, `session-start`-typed one-line output for every non-Codex transport and the exact Codex host-boundary variant, including the marker and already-owned-lock silence path.
It executes the Codex hook interface with `default`, `dontAsk`, and `bypassPermissions` payloads to prove every Codex mode invokes exactly the official session-start path and retains already-owned-lock silence.
It also verifies tracked wrapper registration for Claude, Codex, OpenCode, Pi, and Grok.
`tests/fm-codex-sessionstart-sandbox-live-e2e.test.sh` is the opt-in live Linux reproduction that observes transient namespace-local PID 1 lifetimes, preserves the sandboxed official-lock refusal, and proves a real `approval_policy=never` Codex session makes the same official lock record the host Codex pid.
`tests/fm-captain-translation-contract.test.sh` proves Ahoy's current marker rule, narrow legacy compatibility exclusions, genuine captain-message near misses, and the shared marker on supported user-role operational injections.
`tests/fm-pi-primary-live-e2e.test.sh` and `tests/fm-opencode-primary-live-e2e.test.sh` exercise native startup paths with first-message and later-message Ahoy regressions.
`tests/fm-turnend-guard.test.sh`, `tests/fm-pi-watch-extension.test.sh`, and `tests/fm-daemon.test.sh` cover marked guard, monitoring, and away-mode delivery.

[`verification/supervision.md`](verification/supervision.md#native-session-start-delivery) records the active version-scoped transport evidence.
