"""checks.py の検査定義が期待どおりに通過・ブロックするかを確認する。

    $ python3 config/claude/hooks/tests/run_cases.py
"""

import json
import os
import subprocess
import sys

HOOKS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases.jsonl")
RULES = os.path.join(HOOKS, "..", "..", "agents", "AGENTS.md")

env = dict(os.environ)
env["AGENTS_GATE_SCRIPT"] = os.path.join(HOOKS, "agents-rules-gate.py")
env["AGENTS_CHECKS_FILE"] = os.path.join(HOOKS, "checks.py")
env["AGENTS_RULES_FILE"] = os.path.normpath(RULES)

failures = 0
for line in open(CASES, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    expected, label, payload = json.loads(line)
    proc = subprocess.run(
        ["/bin/sh", os.path.join(HOOKS, "agents-rules-gate.sh")],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
    )
    actual = "PASS" if proc.returncode == 0 else "BLOCK"
    ok = actual == expected
    failures += not ok
    ids = ""
    if actual == "BLOCK":
        ids = " ".join(
            part.split("]")[0] + "]"
            for part in proc.stderr.split("[")[1:]
            if "]" in part
        )
    print(f"{'ok  ' if ok else 'FAIL'} {label:<30} {actual:<5} {ids}")

print(f"\n{failures} failed")
sys.exit(1 if failures else 0)
