#!/usr/bin/env python3
"""Bounded serial current-revision trials. Run with the repository's mise toolchain."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

MODES = ["disabled", "typespec", "structural", "defaults", "compiler", "all"]
PINS = {"livebook": "f18f2035bac89d6c08497f5f2d7e7c4f56e80716",
        "liveview": "8015b9c09a5606f5f3e7204a64ecf9cc28c5b683",
        "ecto": "11784f821a1bb0eedeee59583e311d836cb39ee1"}
APPS = {"fixture": "bylaw_phase_fixture", "livebook": "livebook", "liveview": "phoenix_live_view", "ecto": "ecto"}


def tree_rss(root):
    records = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss="], text=True)
    processes = [tuple(map(int, line.split())) for line in records.splitlines() if line.strip()]
    owned = {root}
    while True:
        children = {pid for pid, ppid, _ in processes if ppid in owned}
        if children <= owned:
            break
        owned |= children
    return sum(rss * 1024 for pid, _, rss in processes if pid in owned)


def run(command, repo, env, log, timeout, memory_mib):
    start = time.monotonic()
    peak = 0
    cutoff = None
    with log.open("x") as stream:
        child = subprocess.Popen(["/usr/bin/time", "-l", *command], cwd=repo, env=env,
                                 stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        while child.poll() is None:
            peak = max(peak, tree_rss(child.pid))
            if time.monotonic() - start > timeout:
                cutoff = "deadline"
            elif peak > memory_mib * 1024 ** 2:
                cutoff = "sampled_tree_rss"
            if cutoff:
                os.killpg(child.pid, signal.SIGKILL)
                break
            time.sleep(.1)
        code = child.wait()
    text = log.read_text()
    match = re.search(r"(\d+)\s+maximum resident set size", text)
    cpu = re.search(r"([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys", text)
    return dict(exit_code=code, elapsed_s=time.monotonic() - start, cutoff=cutoff,
                sampled_tree_peak_bytes=peak, reported_max_rss_bytes=int(match[1]) if match else None,
                cpu_s=float(cpu[2]) + float(cpu[3]) if cpu else None,
                reported_real_s=float(cpu[1]) if cpu else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", choices=APPS)
    parser.add_argument("repo", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--modes", nargs="+", choices=MODES, default=MODES)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--fresh-build", action="store_true")
    parser.add_argument("--selection", nargs="*", default=[])
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--memory-mib", type=int, default=1536)
    args = parser.parse_args()
    qa = Path(__file__).resolve().parent
    package = qa.parent
    repo = args.repo.resolve(strict=True)
    output = args.output.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if args.project in PINS:
        assert revision == PINS[args.project], (revision, PINS[args.project])
        assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=repo)
        assert not args.fresh_build, "Fresh-build comparison is confined to the owned fixture"
    output.mkdir(parents=True, exist_ok=False)
    sources = sorted((package / "lib").rglob("*.ex"))
    manifest = dict(project=args.project, revision=revision, args=vars(args),
                    bylaw_revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=package, text=True).strip(),
                    source_sha256=hashlib.sha256(b"".join(p.read_bytes() for p in sources)).hexdigest(),
                    ebin_sha256=hashlib.sha256(b"".join(p.read_bytes() for p in sorted((package / "_build/test/lib/bylaw_contract/ebin").glob("*.beam")))).hexdigest(),
                    toolchain=subprocess.check_output(["elixir", "--version"], text=True),
                    memory_scope="100ms sampled simultaneous owned process tree; shared pages may count twice")
    (output / "manifest.json").write_text(json.dumps(manifest, default=str, indent=2) + "\n")
    if args.project == "fixture" and not args.fresh_build:
        with (output / "warmup.log").open("x") as log:
            subprocess.run(["mix", "compile"], cwd=repo, env=dict(os.environ, MIX_ENV="test"),
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=args.timeout)
    rows = []
    for trial in range(1, args.trials + 1):
        modes = args.modes if trial % 2 else list(reversed(args.modes))
        for mode in modes:
            name = f"{trial}-{mode}"
            capture = output / f"{name}.etf"
            env = {k: v for k, v in os.environ.items() if not k.startswith("BYLAW_")}
            env.update(MIX_ENV="test", BYLAW_OVERHEAD_MODE=mode, BYLAW_OVERHEAD_OUTPUT=str(capture))
            command = ["elixir"]
            if mode != "disabled":
                ebin = package / "_build/test/lib/bylaw_contract/ebin"
                env.update(BYLAW_OVERHEAD_EBIN=str(ebin), BYLAW_CONTRACT_APPS=APPS[args.project])
                command += ["-pa", str(ebin)]
                if args.diagnostic:
                    env["BYLAW_PHASE_OUTPUT"] = str(output / f"{name}-spans.json")
                    command += ["-r", str(qa / "performance-phase-probe.exs")]
            if args.fresh_build:
                env["MIX_BUILD_PATH"] = str(output / f"{name}-build")
            command += ["-r", str(qa / "overhead-capture.exs"), "-S", "mix", "test", *args.selection,
                        "--seed", "922331", "--max-cases", "4", "--formatter", "ExUnit.CLIFormatter",
                        "--formatter", "BylawOverheadCapture"]
            row = dict(trial=trial, mode=mode, command=command, capture=str(capture),
                       **run(command, repo, env, output / f"{name}.log", args.timeout, args.memory_mib))
            validation = subprocess.run(["elixir", str(qa / "overhead-result.exs"), str(capture), mode],
                                        capture_output=True, text=True)
            row["capture_valid"] = validation.returncode == 0
            row["result"] = json.loads(validation.stdout) if row["capture_valid"] else validation.stderr
            rows.append(row)
            (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
            print(name, row["exit_code"], round(row["elapsed_s"], 3),
                  row["result"].get("coverage_status") if row["capture_valid"] else "missing", flush=True)
    if args.project in PINS:
        assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=repo)
    return int(any(r["exit_code"] or not r["capture_valid"] for r in rows))


if __name__ == "__main__":
    raise SystemExit(main())
