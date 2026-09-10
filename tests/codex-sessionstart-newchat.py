"""Live TUI helper for fm-codex-sessionstart-sandbox-live-e2e.test.sh.

Runs only in the caller's disposable fixture. No real fleet or Codex config is
modified. Native payloads are observed in the fixture before the scope guard.
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import termios
import time

source, lab, codex_home = map(Path, sys.argv[1:])
root = lab / "newchat-primary"
(root / ".codex").mkdir(parents=True)
for name in ("state", "data", "config"):
    (root / name).mkdir()
subprocess.run(["git", "init", "-q", str(root)], check=True)
(root / "AGENTS.md").write_text("Answer the probe without tools.\n")
shutil.copytree(source / "bin", root / "bin")
shutil.copytree(source / "docs/supervision-protocols", root / "docs/supervision-protocols")
shutil.copyfile(source / ".codex/hooks.json", root / ".codex/hooks.json")
hook = root / "bin/fm-codex-sessionstart-hook.sh"
text = hook.read_text().replace(
    'exec "$SCRIPT_DIR/fm-session-start.sh"',
    'printf "%s\\n" "$session_id" >> "$SCRIPT_DIR/../native-events"\n'
    'exec "$SCRIPT_DIR/fm-session-start.sh"',
)
hook.write_text(text)
# Trust only this generated project in the already isolated test home.
with (codex_home / "config.toml").open("a") as config:
    config.write(f'\n[projects.{json.dumps(str(root))}]\ntrust_level = "trusted"\n')
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
env = dict(os.environ, CODEX_HOME=str(codex_home), TERM="xterm-256color")
for name in ("FM_HOME", "FM_ROOT_OVERRIDE", "FM_STATE_OVERRIDE", "FM_DATA_OVERRIDE", "FM_CONFIG_OVERRIDE"):
    env.pop(name, None)
prompt = "Without tools, return only the value of NATIVE_CONTEXT_SENTINEL from your startup context."
(root / "data/captain.md").write_text("NATIVE_CONTEXT_SENTINEL=NATIVE_FLEET_CONTEXT_1\n")
process = subprocess.Popen(
    ["codex", "-C", str(root), "-a", "never", "-s", "workspace-write",
     "--dangerously-bypass-hook-trust", "--no-alt-screen", prompt],
    stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True,
)
os.close(slave)
buffer = ""
ansi = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]")


def receive_until(predicate, timeout=90):
    global buffer
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        if process.poll() is not None:
            raise RuntimeError("Codex exited before native lifecycle assertion")
        if select.select([master], [], [], 0.1)[0]:
            buffer = (buffer + os.read(master, 65536).decode(errors="replace"))[-1_000_000:]
    raise RuntimeError("Timed out waiting for native new-chat lifecycle")


def send(text):
    os.write(master, b"\x1b[200~" + text.encode() + b"\x1b[201~")
    # Separate text insertion and Enter so the TUI does not treat Enter as part
    # of a rapid multiline paste. This is presentation timing, not a test oracle.
    time.sleep(0.8)
    os.write(master, b"\r")


try:
    owner = None
    for index in (1, 2):
        marker = f"NATIVE_FLEET_CONTEXT_{index}"
        (root / "data/captain.md").write_text(f"NATIVE_CONTEXT_SENTINEL={marker}\n")
        if index == 2:
            send("/new")
            time.sleep(0.8)
            send(prompt)
        receive_until(lambda: f"• {marker}" in ansi.sub("", buffer))
        receipts = [p for p in (root / "state/.codex-startup").iterdir() if not p.name.startswith(".")]
        assert len(receipts) == index, "new chat did not complete exactly one native startup"
        current_owner = (root / "state/.lock").read_text().strip()
        assert current_owner.isdigit() and current_owner != "1", "invalid native host owner"
        if owner is not None:
            assert current_owner == owner, "new chat changed the long-lived host process"
        owner = current_owner
        assert all(p.read_text().strip() == owner for p in receipts), "receipt lost host binding"
    identities = (root / "native-events").read_text().splitlines()
    assert len(identities) == 2 and len(set(identities)) == 2, "native payload did not distinguish new chats"
    send("/quit")
    process.wait(timeout=10)
    # Inspect only this test's two generated rollouts. The sentinel response
    # must come from native context, not a model shell read of the fixture.
    for identity in identities:
        rollouts = list((codex_home / "sessions").rglob(f"rollout-*{identity}.jsonl"))
        assert len(rollouts) == 1, "missing fixture rollout for native context verification"
        for line in rollouts[0].read_text().splitlines():
            record = json.loads(line)
            payload = record.get("payload", {})
            if record.get("type") == "response_item":
                assert payload.get("type") not in {
                    "function_call", "custom_tool_call", "local_shell_call"
                }, "Codex used a tool instead of receiving native fleet context"
    print("ok - Codex TUI /new delivered two distinct native session IDs, one host owner, and fresh fleet context in each chat")
except Exception:
    (lab / "newchat-tui.log").write_text(ansi.sub("", buffer))
    raise
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    os.close(master)
