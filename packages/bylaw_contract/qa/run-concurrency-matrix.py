#!/usr/bin/env python3
"""Serial alternating compilation/execution concurrency controls using the phase runner."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

SETTINGS = {"native": ("default", "default"), "requires-1": ("1", "default"),
            "requires-4": ("4", "default"), "cases-1": ("default", "1"),
            "cases-4": ("default", "4"), "both-1": ("1", "1"), "both-4": ("4", "4")}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("project", choices=["fixture", "ecto", "livebook"])
parser.add_argument("repo", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--trials", type=int, default=3)
parser.add_argument("--settings", choices=SETTINGS, nargs="+", default=list(SETTINGS))
parser.add_argument("--diagnostic", action="store_true")
parser.add_argument("--selection", nargs="*", default=[])
args = parser.parse_args()
assert args.trials > 0
qa = Path(__file__).resolve().parent
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
rows = []
for trial in range(1, args.trials + 1):
    settings = args.settings if trial % 2 else list(reversed(args.settings))
    modes = ["disabled", "defaults"] if trial % 2 else ["defaults", "disabled"]
    if args.diagnostic:
        modes = ["defaults"]
    for setting in settings:
        requires, cases = SETTINGS[setting]
        child_output = output / f"{trial}-{setting}"
        command = [sys.executable, str(qa / "run-performance-phases.py"), args.project,
                   str(args.repo.resolve()), str(child_output), "--trials", "1", "--modes", *modes,
                   "--max-requires", requires, "--max-cases", cases]
        if args.diagnostic:
            command += ["--diagnostic"]
        if args.selection:
            command += ["--selection", *args.selection]
        with (output / f"{trial}-{setting}.log").open("x") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        row = dict(trial=trial, setting=setting, command=command, exit_code=result.returncode)
        for name in ["manifest", "results"]:
            path = child_output / f"{name}.json"
            row[name] = json.loads(path.read_text()) if path.exists() else None
        if args.diagnostic:
            for name in ["spans", "queues"]:
                path = child_output / f"1-defaults-{name}.json"
                row[name] = json.loads(path.read_text()) if path.exists() else None
        rows.append(row)
        (output / "matrix.json").write_text(json.dumps(rows, indent=2) + "\n")
        print(trial, setting, result.returncode, flush=True)
raise SystemExit(int(any(row["exit_code"] for row in rows)))
