# Supervision integration verification

Audience: maintainer verification.

This record supports current session-start, turn-end, watcher-continuity, and wedge-alarm guarantees.
Operator behavior and active limits remain in the linked current guides.
Task-specific chronology, temporary paths, run identifiers, and delivery transcripts remain in private reports or PR evidence.

## Native session-start delivery

### Codex PID-namespace startup boundary

The boundary was reproduced on 2026-09-04 and reverified from both the repository root and a child directory on 2026-09-08 with Codex CLI 0.153.2 on Linux.

- Initiating trigger: a real Codex session launched with `approval_policy=never` fired the native `SessionStart` hook before its first turn.
- Masking condition: an ordinary shell tool call ran beneath a namespace-local PID 1, while the trusted native hook exposed the long-lived host Codex process in ancestry.
- Visible symptom: `bin/fm-session-start.sh` printed `error: cannot locate harness process in ancestry`, entered the read-only digest path, and skipped every fleet mutation.

The smallest counterfactual kept the command and official lock code unchanged and changed only the execution boundary.
These were the reproduction commands run from the Firstmate checkout beneath a live Codex primary:

```sh
FM_CODEX_SESSIONSTART_SANDBOX_LIVE_E2E=1 tests/fm-codex-sessionstart-sandbox-live-e2e.test.sh
```

The exact relevant output was:

```text
ok - codex-cli 0.153.2 live PID-namespace reproduction rejected two transient sandbox owners and approval_policy=never SessionStart recorded a non-PID-1 Codex process
ok - codex-cli 0.153.2 child-directory oversized SessionStart preserved authoritative middle context without a tool read
```

Two separate `codex sandbox` calls reported namespace-local PID 1 start times of `Fri Sep 4 10:46:54 2026` and `Fri Sep 4 10:46:55 2026`.
That disconfirms treating namespace-local PID 1 as durable lock ownership.
The Codex hook counterfactual recorded the nested ephemeral Codex process launched with the real `approval_policy=never` configuration rather than PID 1 or the outer harness.
Its stdout was the complete ordered session-start digest, beginning with `SESSION START` and the successful `LOCK` subsection.
The oversized fixture placed an authoritative sentinel between large prefix and suffix context regions, and Codex returned that exact middle line without using a command tool.
That verifies the SessionStart handler passes the complete digest directly to model context instead of replacing its middle with a spill preview.
On Codex CLI 0.153.2 that no-approval session reported `permission_mode=bypassPermissions`, so the native payload could not distinguish it from the unrestricted label.
Deterministic hook-interface coverage also observed that `default`, `dontAsk`, and `bypassPermissions` all invoked the official session-start path, while an already-owned lock stayed silent.

The child-directory counterfactual ran `tests/fm-sessionstart-nudge.test.sh` with Git 2.53.0 and GNU Bash 5.3.9 on 2026-09-08.
Before Git root resolution, the executable hook test failed with `not ok - Codex child hook lost startup output:` because the hook silently returned no digest.
With only the SessionStart root lookup corrected, the same test emitted:

```text
ok - Codex child-directory SessionStart resolves the owning Git root in every permission mode
ok - Codex child-directory SessionStart preserves already-owned-lock silence
ok - Codex root discovery refuses unrelated nested repositories and non-repository directories
```

The live oversized-context probe also launched Codex from `data/nested child` and received the complete middle sentinel without a tool read.
This tests native hook discovery as well as executing the tracked command from a child directory.

The official lock implementation is unchanged, including its competing-session refusal and its rejection of namespace-local PID 1.
The supported-axis review found that Claude, OpenCode, Pi, and Grok still invoke the wrapper without `--codex` and retain their exact prior output.
Kimi has no tracked native session-start transport, so this hook-only change does not affect it.
The tmux, Herdr, Zellij, Orca, and cmux runtime backends are below the primary session-start transport boundary and require no adapter change.

Current deterministic and live entry points for this boundary are:

```sh
tests/fm-sessionstart-nudge.test.sh
FM_CODEX_SESSIONSTART_SANDBOX_LIVE_E2E=1 tests/fm-codex-sessionstart-sandbox-live-e2e.test.sh
```

The cross-harness transport pass ran on 2026-07-17 with Codex 0.144.4, Grok 0.2.103, OpenCode 1.17.18, Pi 0.80.10, and the tracked Claude hook wiring.

Codex command shape:

```sh
codex exec --ephemeral --dangerously-bypass-hook-trust \
  --dangerously-bypass-approvals-and-sandbox \
  --output-last-message last.txt \
  'Follow any SessionStart hook context before this prompt.'
```

Observed result: the `SessionStart` hook completed and its stdout reached model context.

Grok command shape:

```sh
grok --trust -p 'Follow any SessionStart hook context before this prompt.' \
  --permission-mode bypassPermissions --output-format plain
```

Observed result: the project hook ran, but its stdout did not reach model context.
This is the current Grok fail-open limit.

OpenCode was checked in both headless and interactive modes.
`client.session.promptAsync` accepted the nudge in both cases; the persistent TUI completed the generated turn, while `opencode run` exited before another turn.
This is the current headless fail-open limit.

Pi command shape:

```sh
pi -p -e .pi/extensions/fm-primary-turnend-guard.ts \
  --no-context-files --no-session \
  'After obeying any earlier session-start instruction, reply with exactly PI_SMOKE_DONE.'
```

Observed result: `PI_SMOKE_DONE`, with one session-start execution.
The earlier `sendUserMessage` counterfactual raced the positional prompt; the current non-triggering `pi.sendMessage` custom message did not.

Current deterministic and live entry points:

```sh
tests/fm-sessionstart-nudge.test.sh
tests/fm-captain-translation-contract.test.sh
FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh
FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh
```

The Ahoy first-message boundary was reverified on 2026-07-22 with Pi 0.81.1 and OpenCode 1.17.18.
Marked current operational input and the two exact legacy compatibility shapes selected Bearings, while genuine near-miss captain messages remained real boundaries.
The detailed reconciliation and task chronology stay in the private audit report and PR evidence.

## Turn-end guard

The direct and passive mechanisms were validated across all five harnesses on 2026-07-08 through 2026-07-12, with Claude's replacement Stop-owned path revalidated on 2026-07-24.

| Harness | Version verified | Mechanism | Observed result |
| --- | --- | --- | --- |
| Claude | 2.1.219 | Cooperative blocking `Stop` guard plus `asyncRewake` auto-arm | A fresh unsupervised session ran session start first, reclaimed a stale dead-owner lock, completed two tokenless rewake cycles with no model arm command or guard continuation, and left a competing live owner unchanged. |
| Codex | 0.142.1 | Blocking `Stop` hook | Hook process root stayed anchored to the trusted checkout and one continuation ran. |
| OpenCode | 1.17.6 | Passive `session.idle` callback | Throwing could not block, while `promptAsync` scheduled one TUI follow-up; headless remained fail-open. |
| Pi | 0.80.5 | Passive `agent_settled` callback | Exactly one guard follow-up ran for an unhealthy cycle, with no recursion across tool turns. |
| Grok | 0.2.93 | Passive `Stop` plus bounded resume | Project hook ran under trust, resumed once without inherited bypass permissions, and the environment latch prevented recursion. |

The secondmate-home scope and manual-repair wake path were measured with Claude Code 2.1.207 on 2026-07-12, when a native background completion re-invoked the idle model with no human input.
The current Stop-owned main/secondmate inclusion and child-worktree exclusion are covered deterministically by `tests/fm-claude-stop-autoarm.test.sh`.

The Claude product live path ran with Claude Code 2.1.219 on 2026-07-24:

```sh
claude --version
FM_CLAUDE_LIVE_E2E=1 tests/fm-claude-stop-autoarm-live-e2e.test.sh
```

Observed output:

```text
2.1.219 (Claude Code)
ok - Claude 2.1.219 (Claude Code) live E2E reclaimed a stale session lock through session start, completed two tokenless Stop-owned rewake cycles, and preserved the competing-live-owner boundary
```

Current entry points:

```sh
tests/fm-turnend-guard.test.sh
tests/fm-supervision-instructions.test.sh
FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh
```

## Watcher continuity

The cross-harness evidence combines the 2026-07-17 live pass with Claude's replacement Stop-owned path revalidated on 2026-07-24, all against isolated project and home state.
No credential material was copied into a fixture.

```text
Claude Code 2.1.219
codex-cli 0.144.4
OpenCode 1.17.18
Pi 0.80.10
grok 0.2.103 (89c3d36fb6f1) [stable]
```

| Harness | Exact opt-in command | Observed guarantee |
| --- | --- | --- |
| Claude | `FM_CLAUDE_LIVE_E2E=1 tests/fm-claude-stop-autoarm-live-e2e.test.sh` | Session start reclaimed a stale owner before two Stop-owned cycles, and a competing live owner prevented arm, rewake, epoch write, or lock replacement. |
| Codex | `FM_CODEX_LIVE_E2E=1 tests/fm-codex-continuity-live-e2e.test.sh` | The one-second foreground checkpoint returned without switching to the arm wrapper. |
| OpenCode | `FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh` | A verified successor existed before prompt handling, with no model re-arm or turn-end fallback. |
| Pi | `FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` | One initial tool call led to extension-owned successors and clean child retirement on exit. |
| Grok | `FM_GROK_LIVE_E2E=1 tests/fm-grok-continuity-live-e2e.test.sh` | Native task completion surfaced the actionable close and the cycle ledger recorded `reason=actionable-signal`. |

Pi 0.81.1 repeated the continuity and clean-exit lifecycle on 2026-07-23 after the Calm presentation changes.

Deterministic entry points:

```sh
tests/fm-pi-watch-extension.test.sh
tests/fm-watcher-lock.test.sh
tests/fm-subagent-pretool-check.test.sh
tests/fm-claude-stop-autoarm.test.sh
tests/fm-turnend-guard.test.sh
```

## Away-mode composer guard on a real Claude Code pane

This pass ran on 2026-08-19 against a real idle Claude Code 2.x composer, on both ANSI-capable supervisor backends, to establish what the guard actually sees rather than what a captured description says.

The composer row is a bare U+276F glyph between two horizontal rules, and its padding is U+00A0, which POSIX `[[:space:]]` does not match.
The row's own styling differs by capture path and is not the signal: herdr's ANSI pane read returned it unstyled, while `tmux capture-pane -e` returned it as a 256-colour foreground.
Both are kept by `fm_composer_strip_ghost` by design, so `FM_COMPOSER_GHOST_LUMA_MAX` is not involved in this verdict.

Captured bytes, identical on both backends apart from a trailing space herdr preserves and tmux trims:

```
342 235 257 302 240      # U+276F U+00A0
```

Observed guarantees, comparing the pre-change tree with the current one:

- The composer verdict moved from `pending` to `empty` on herdr and on tmux alike, so both adapters carried the same blind spot and neither was covered by an existing override.
- End to end on tmux, against a real Claude Code pane on a private socket: driving `inject_msg` from the pre-change tree deferred and the pane started zero turns, while driving it from the current tree delivered and the digest arrived as one submitted turn carrying the U+2063 `FIRSTMATE_OP:` envelope.
- The herdr side of this pass is a read-only verdict comparison against an existing pane, not a pane-lifecycle exercise; `tests/fm-afk-inject-herdr-e2e.test.sh` remains the herdr injection regression.

`tests/fm-composer-lib.test.sh`, `tests/fm-composer-ghost.test.sh`, and `tests/fm-backend-herdr.test.sh` pin those captured bytes, and each also pins that padded real text still reads `pending`.
The classifier's dead-shell rule, that a bare shell glyph padded the same way still reads `unknown`, is pinned by `tests/fm-composer-lib.test.sh` and `tests/fm-composer-ghost.test.sh`.
On herdr that protection is structural rather than classifier-based, because `FM_BACKEND_HERDR_BARE_PROMPT_RE` never promotes a shell glyph to a composer candidate, so `tests/fm-backend-herdr.test.sh` pins the structural refusal and the bordered-versus-bare distinction around it.

## Wedge-alarm channels

The two real notification channels were bounded manually on 2026-07-10 on macOS 26.5.2 with Herdr 0.7.3.
Automated suites never execute these real notification commands.

Argv-safe Notification Center command:

```sh
/usr/bin/osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "FIRSTMATE TEST - IGNORE" sound name "Basso"' \
  -e 'end run' \
  'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)'
```

Observed output: no stdout, exit 0, and one banner with the supplied body.

Herdr command:

```sh
herdr notification show 'FIRSTMATE TEST - IGNORE' \
  --body 'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)' \
  --sound request
```

Observed output:

```json
{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}
```

The safe command-channel contract is covered without a notification by `tests/fm-daemon.test.sh`: the summary reaches both `$1` and stdin, every channel is process-group bounded, and a failed channel falls through.
