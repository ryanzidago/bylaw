#!/usr/bin/env python3
"""Run native, allocation, and repeated-session diagnostics serially with bounds."""
import importlib.util
import json
import os
from pathlib import Path
import sys

qa = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("phase_runner", qa / "run-performance-phases.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=False)
repo = qa / "performance_phase_fixture"
ebin = qa.parent / "_build/test/lib/bylaw_contract/ebin"
base = {k: v for k, v in os.environ.items() if not k.startswith("BYLAW_")}
base.update(MIX_ENV="test")
rows = []


def run(name, command, env, cwd=repo):
    row = dict(name=name, command=command, cwd=str(cwd),
               **runner.run(command, cwd, env, output / f"{name}.log", 120, 1536))
    rows.append(row)
    (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(name, row["exit_code"], flush=True)


for mode in runner.MODES:
    directory = output / f"warm-{mode}"
    directory.mkdir()
    env = dict(base, BYLAW_OVERHEAD_MODE=mode, BYLAW_CONTRACT_APPS="bylaw_phase_fixture",
               BYLAW_WARM_OUTPUT=str(directory), BYLAW_OVERHEAD_EBIN=str(ebin))
    run(f"warm-{mode}", ["mix", "run", str(qa / "performance-warm-sessions.exs")], env)

for mode in ["typespec", "structural", "defaults", "compiler"]:
    env = dict(base, BYLAW_OVERHEAD_MODE=mode, BYLAW_OVERHEAD_EBIN=str(ebin))
    run(f"allocation-{mode}", ["mix", "run", str(qa / "performance-allocation.exs")], env)

run("profile-require", ["mix", "test", "--profile-require", "time", "--seed", "922331"], base)
run("compile-profile", ["mix", "compile.elixir", "--force", "--profile", "time"], base)
run("mix-profile", ["mix", "test", "--seed", "922331", "--max-cases", "4"],
    dict(base, MIX_PROFILE="test", MIX_PROFILE_FLAGS="--type time --report process"))
if len(sys.argv) > 2:
    livebook = Path(sys.argv[2]).resolve(strict=True)
    import subprocess
    assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=livebook, text=True).strip() == runner.PINS["livebook"]
    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=livebook)
    for mode in ["typespec", "structural"]:
        run(f"livebook-allocation-{mode}", ["mix", "run", str(qa / "performance-allocation.exs")],
            dict(base, BYLAW_OVERHEAD_MODE=mode, BYLAW_OVERHEAD_EBIN=str(ebin)), livebook)
    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=livebook)
# Native profiling is diagnostic; do not mix its elapsed time into normal trials.
raise SystemExit(int(any(r["exit_code"] for r in rows)))
