#!/usr/bin/env python3
"""Bounded real-formatter lifecycle diagnostic; failures survive subsequent success."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
qa = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("phase_runner", qa / "run-performance-phases.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--scenarios", default="complete,complete,complete")
parser.add_argument("--mode", choices=["typespec", "structural", "defaults", "compiler", "all"], default="defaults")
parser.add_argument("--repo", type=Path, default=qa / "performance_phase_fixture")
parser.add_argument("--tests", nargs="+", default=[])
parser.add_argument("--diff-base")
args = parser.parse_args()
assert all(x in {"complete", "failure", "overflow", "scoped", "scope_error"} for x in args.scenarios.split(","))
assert not (args.mode == "compiler" and "overflow" in args.scenarios.split(",")), "Compiler observation has no trace queue"
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
repo = args.repo.resolve(strict=True)
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
if repo != qa / "performance_phase_fixture":
    assert revision in runner.PINS.values(), "QA checkout must match an approved pin"
    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=repo)
    assert args.tests, "External QA requires explicit test files"
    assert not {"failure", "overflow"}.intersection(args.scenarios.split(",")), "Fault injection requires the fixture"
env = {k: v for k, v in os.environ.items() if not k.startswith("BYLAW_")}
env.update(MIX_ENV="test", BYLAW_WARM_EBIN=str(qa.parent / "_build/test/lib/bylaw_contract/ebin"),
           BYLAW_WARM_OUTPUT=str(output), BYLAW_WARM_SCENARIOS=args.scenarios, BYLAW_WARM_MODE=args.mode,
           BYLAW_CONTRACT_REPORT="summary", BYLAW_WARM_TESTS=",".join(args.tests))
if args.diff_base:
    env["BYLAW_WARM_DIFF_BASE"] = args.diff_base
compile_resource = runner.run(["mix", "compile"], repo, env, output / "compile.log", 120, 1536)
(output / "compile-resources.json").write_text(json.dumps(compile_resource, indent=2) + "\n")
if compile_resource["exit_code"]:
    raise SystemExit(compile_resource["exit_code"])
command = ["mix", "run", str(qa / "warm-lifecycle.exs")]
resource = runner.run(command, repo, env, output / "run.log", 60, 1536)
sources = list((qa.parent / "lib").rglob("*.ex")) + [
    qa / name for name in ["run-warm-lifecycle.py", "warm-lifecycle.exs", "warm-lifecycle-capture.exs", "warm-session-tests.exs"]
]
sources += list((qa / "performance_phase_fixture").rglob("*.ex"))
resource.update(command=command, repo=str(repo), repo_revision=revision, mode=args.mode,
                scenarios=args.scenarios, tests=args.tests, diff_base=args.diff_base,
                toolchain=subprocess.check_output(["elixir", "--version"], cwd=repo, text=True).strip(),
                bylaw_revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=qa, text=True).strip(),
                source_sha256={str(p.relative_to(qa.parent)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
(output / "resources.json").write_text(json.dumps(resource, indent=2) + "\n")
print(json.dumps(resource))
if repo != qa / "performance_phase_fixture":
    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=repo)
raise SystemExit(resource["exit_code"])
