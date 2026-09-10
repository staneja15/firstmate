# Native session-start nudge

AGENTS.md section 3 is the authoritative behavioral contract for session start.
The tracked native adapters inject one instruction and never run the digest, acquire the lock, perform bootstrap work, drain notifications, or arm supervision themselves, except for the Codex path described below.
Every nudge payload starts with U+2063 and the stable `FIRSTMATE_OP: ` label and carries the current `session-start` protocol kind.
The non-Codex payload retains exactly ``Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.`` as its body.
The Codex wrapper variant describes host recovery; its native transport uses the shared scope predicates and passes the native session identity to the composed command.
The Ahoy skill owns the rule that this marked operational input is never a captain-authored session boundary, including its narrow legacy compatibility cases.

## Shared wrapper and safety

`bin/fm-sessionstart-nudge.sh` is the scope and process-idempotence guard for the nudge transports.
The Codex adapter instead uses `bin/fm-codex-sessionstart-hook.sh` with the same gate and primary-scope predicates and native chat identity; every other adapter invokes the wrapper directly with no argument and retains its original output byte-for-byte.
It sources `bin/fm-gate-refuse-lib.sh` and stays silent for a no-mistakes gate agent identified by `NO_MISTAKES_GATE` or a `.no-mistakes/repos/*.git` git-common-dir.
It shares `bin/fm-primary-scope-lib.sh` with `bin/fm-turnend-guard.sh`, so the hooks use one primary-detection owner.
The Shared Predicate section of [`turnend-guard.md`](turnend-guard.md#shared-predicate) owns marker validation, plain-checkout detection, and required Firstmate-shaped paths.

Before printing, the wrapper reads `state/.lock` and walks at most eight parents from its own pid, matching `bin/fm-lock.sh` and Pi's `lockOwnership()` ancestry depth.
If the lock names a live pid in that ancestry, session start already ran in this harness session and the wrapper stays silent.
Every path exits 0, including malformed state and adapter errors, because a Claude SessionStart exit 2 blocks session initialization.

Codex can execute ordinary shell tool calls inside a per-command PID namespace whose local PID 1 is the transient `codex-linux-sandbox` launcher.
In that mode the official lock cannot see the long-lived host Codex ancestor.
The native payload does not expose a reliable distinction between `approval_policy=never` and unrestricted sessions: both can report `permission_mode=bypassPermissions`.
When Codex delivers the enabled, trusted native event, the hook runs the one official `bin/fm-session-start.sh` invocation directly and returns its digest as developer context for every Codex permission mode.
The handler's context limit in `.codex/hooks.json` is intentionally uncapped so authoritative middle content reaches the model, preserving AGENTS.md's read-once digest contract.
The hook validates primary scope, no-mistakes gate refusal, and the native `session_id` before invoking composed startup.
`bin/fm-session-start.sh` owns the native completion receipt and serialization mechanics: each new chat gets a complete digest even when the process already owns the fleet, while repeated delivery for an already-completed chat stays silent after host ownership is verified.
Missing or invalid native identity produces an actionable recovery diagnostic without guessing a chat identity.
The official lock remains the authority for verifying and recording the host Codex process.
This boundary is scoped to the official startup command and does not provide general host command execution.
Unrestricted sessions use the same trusted hook path; the official command and lock verification remain unchanged.
A hook file on disk is not proof that the current thread received its digest; use the recovery procedure below when native context is absent.

## Codex startup recovery

If the complete native `SESSION START` digest is already in context, read it once and follow its result without invoking startup again.
If it is absent, run the same official command through a supported host execution tool in the current Codex session, preserving the Firstmate home and working directory.
An already-authorized host tool needs no new permission; use shell escalation only when that session actually exposes and permits it.
A permission label alone does not prove host PID visibility.
When no supported host tool is available, report that execution-boundary blocker and the need for a trusted native startup; do not invent a namespace escape, grant broader sandbox access, or launch a replacement owner from a separate shell.
`bin/fm-session-start.sh` owns the exact failure diagnostic and retry mechanics.
Its unresolved-ancestry result is an incomplete preflight: it does not run bootstrap or publish a context/fleet digest, and it does not establish that another host session owns the fleet.
A completed host invocation still refuses a competing live owner, and that refusal remains read-only.
Never delete or overwrite a live owner's lock to recover startup.

For missing native delivery, inspect the effective project root, enabled hook configuration, and Codex's native hook trust status for the exact current command.
Project trust and hook-command trust are separate checks; review and enable/trust only the Firstmate hook in Codex's native hook UI when it is missing or modified.
Do not hand-write trust hashes or use a global hook-trust bypass as an installation repair.
Changes to hook files or trust configuration do not replay a past startup event.
Codex native startup uses the chat identity independently of process ownership, so `/new` can receive fresh fleet context while retaining the same verified host lock.
Check the native lifecycle actually used by the current thread before attributing absence to process age, cached configuration, or trust.
The supported startup and counterfactual verification entries below distinguish native delivery from direct execution of a hook command.

## Harness transports

| Harness | Tracked transport | Current compatibility |
| --- | --- | --- |
| Claude | `.claude/settings.json` registers `SessionStart` for `startup`, `resume`, and `clear`, excludes `compact`, and invokes the wrapper through `CLAUDE_PROJECT_DIR`. | Native stdout context injection is supported. |
| Codex | `.codex/hooks.json` resolves the owning Git root from the hook process working directory, verifies a Firstmate-shaped hook-bearing root, and executes `bin/fm-codex-sessionstart-hook.sh`. | Enabled, trusted native delivery executes the official command in the host hook; absent delivery follows Codex startup recovery above. |
| OpenCode | `.opencode/plugins/fm-primary-sessionstart-nudge.js` listens for `session.created`, runs once per session id, and calls `client.session.promptAsync` only when the wrapper prints a nudge. | Interactive TUI delivery is supported; headless `opencode run` is intentionally fail-open because the process can exit before the queued turn. |
| Pi | `.pi/extensions/fm-primary-turnend-guard.ts` handles `session_start` reasons `startup`, `new`, and `resume`, then injects the wrapper output with `pi.sendMessage`. | The custom message reaches model context without racing an initial positional prompt. |
| Grok | `.grok/hooks/fm-primary-sessionstart-nudge.json` registers a project `SessionStart` hook and invokes the wrapper through inline-defaulted `${GROK_WORKSPACE_ROOT:-}`. | The project hook runs when the checkout is trusted, but Grok currently discards hook stdout from model context, so this path is intentionally fail-open. |

The OpenCode nudge runs only on `session.created`.
The watcher-arm and turn-end plugins run later on `session.idle`, and the guard lets the watcher coordinator act first, so the plugins do not race for one lifecycle event.

Grok's guaranteed-loading alternative is a global token-guarded hook like the pattern used by `bin/fm-spawn.sh`.
That alternative expands trust and writes outside this repository, so Firstmate never installs it or grants folder trust automatically.

## Regression coverage

`tests/fm-session-start.test.sh` proves unresolved ancestry preserves the host lock and wake queue without probing authentication or publishing a digest, while genuine competing-owner refusal retains detect-only bootstrap and the read-only digest.
`tests/fm-sessionstart-nudge.test.sh` proves wrapper silence for both gate signals, an unmarked linked worktree, a missing state directory, and an already-owned lock.
It proves the exact original U+2063 `FIRSTMATE_OP:`-prefixed, `session-start`-typed one-line output for every non-Codex transport and the exact Codex host-boundary variant, including the marker and already-owned-lock silence path.
It executes the Codex hook interface with `default`, `dontAsk`, and `bypassPermissions` payloads to prove every Codex mode passes the native identity to the official session-start path even with an already-owned process lock.
Child-directory invocations resolve the owning Git root and refuse unrelated nested repositories or directories outside Git.
The composed startup tests cover same-chat silence, new-chat fresh context, and competing-owner refusal with an existing receipt.
It also verifies tracked wrapper registration for Claude, Codex, OpenCode, Pi, and Grok.
`tests/fm-codex-sessionstart-sandbox-live-e2e.test.sh` is the opt-in live Linux reproduction that observes transient namespace-local PID 1 lifetimes, preserves the sandboxed official-lock refusal, and proves a real `approval_policy=never` Codex session makes the same official lock record the host Codex pid.
Its `tests/codex-sessionstart-newchat.py` helper exercises the real TUI first prompt and `/new`, observing distinct native identities, unchanged host ownership, and fresh model-visible fleet context in each chat.
`tests/fm-captain-translation-contract.test.sh` proves Ahoy's current marker rule, narrow legacy compatibility exclusions, genuine captain-message near misses, and the shared marker on supported user-role operational injections.
`tests/fm-pi-primary-live-e2e.test.sh` and `tests/fm-opencode-primary-live-e2e.test.sh` exercise native startup paths with first-message and later-message Ahoy regressions.
`tests/fm-turnend-guard.test.sh`, `tests/fm-pi-watch-extension.test.sh`, and `tests/fm-daemon.test.sh` cover marked guard, monitoring, and away-mode delivery.

[`verification/supervision.md`](verification/supervision.md#native-session-start-delivery) records the active version-scoped transport evidence.
