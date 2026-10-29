#!/usr/bin/env python3
"""Read-only proxy integration test: launch the real monitor against a fake CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="harem-proxy-") as tmp:
    tmp = Path(tmp)
    fake = tmp / "codex"
    fake.write_text('''#!/usr/bin/env python3
import json, sys
step = 0
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get("method")
    if method == "initialize":
        print(json.dumps({"id":msg["id"], "result":{"userAgent":"fixture"}}), flush=True)
    elif method == "thread/loaded/list":
        print(json.dumps({"id":msg["id"], "result":{"data":["older-loaded"]}}), flush=True)
    elif method == "thread/read":
        assert msg["params"] == {"threadId":"older-loaded", "includeTurns":False}
        print(json.dumps({"id":msg["id"], "result":{"thread":{"id":"older-loaded","status":{"type":"active","activeFlags":[]},"updatedAt":0}}}), flush=True)
    elif method == "thread/list":
        statuses = [{"type":"active","activeFlags":[]}, {"type":"active","activeFlags":["waitingOnApproval"]}, {"type":"systemError"}, {"type":"idle"}]
        status = statuses[min(step, len(statuses)-1)]
        step += 1
        print(json.dumps({"id":msg["id"],"result":{"data":[{"id":"fixture","name":"Test thread","updatedAt":step,"status":status}],"nextCursor":None}}), flush=True)
    elif method != "initialized":
        raise RuntimeError("Unexpected request: " + method)
''')
    fake.chmod(0o755)
    result = subprocess.run([str(ROOT / ".build/debug/codex-harem"), "--home", str(tmp), "--codex", str(fake), "--probe", "7"], text=True, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    for status in ["thinking", "waiting", "failed", "idle"]:
        assert f"fixture:{status}" in result.stdout, result.stdout
    assert "older-loaded:thinking" in result.stdout, result.stdout
    assert "Connected to shared Codex server" in result.stdout, result.stdout
    print("Proxy handshake, polling, and thinking → waiting → failed → idle: passed")
    # A dead proxy must leave rollout monitoring live and reconnect on its own.
    thread_id = "00000000-0000-4000-8000-000000000001"
    sessions = tmp / "sessions/2026/10/30"
    sessions.mkdir(parents=True)
    (sessions / f"rollout-2026-10-30T00-00-00-{thread_id}.jsonl").write_text(json.dumps({"type":"event_msg","payload":{"type":"task_started"}}) + "\n")
    attempts = tmp / "attempts"
    fake.write_text(f'''#!/usr/bin/env python3
from pathlib import Path
p = Path({str(attempts)!r})
with p.open("a") as f: f.write("attempt\\n")
raise SystemExit(1)
''')
    result = subprocess.run([str(ROOT / ".build/debug/codex-harem"), "--home", str(tmp), "--codex", str(fake), "--probe", "13"], text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, result.stderr
    assert "shared Codex server unavailable" in result.stdout, result.stdout
    assert f"{thread_id}:thinking" in result.stdout, result.stdout
    assert len(attempts.read_text().splitlines()) >= 2, "Proxy was not retried"
    print("Proxy exit → session-log fallback → automatic retry: passed")
