#!/usr/bin/env python3
"""Serial fresh-VM pairs on pinned, approved QA repos; require terminal captures.

Run under the chosen mise toolchain. Output directory must not already exist.
Compilation/dependency preparation is a separate, recorded warmup step.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

PINS = {
    "livebook": ("livebook", "f18f2035bac89d6c08497f5f2d7e7c4f56e80716"),
    "liveview": ("phoenix_live_view", "8015b9c09a5606f5f3e7204a64ecf9cc28c5b683"),
    "realtime": ("realtime", "21ce9acb5a171b07d7494a80fe0a3f2d008f5710"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", choices=PINS)
    parser.add_argument("repo", type=Path)
    parser.add_argument("ebin", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seed", type=int, default=922331)
    parser.add_argument("--max-cases", type=int, default=28)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--enabled-mode", choices=["all", "typespec", "structural", "defaults", "compiler"],
                        default="all")
    parser.add_argument("--selection", nargs="*", default=[])
    args = parser.parse_args()
    app, pin = PINS[args.project]
    repo = args.repo.resolve(strict=True)
    ebin = args.ebin.resolve(strict=True)
    output = args.output.resolve()
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if actual != pin:
        raise SystemExit(f"Expected pinned {args.project} revision {pin}; found {actual}")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=repo):
        raise SystemExit("QA checkout must be clean before the paired runs")
    output.mkdir(parents=True, exist_ok=False)
    scripts = Path(__file__).resolve().parent
    rows = []
    enabled = args.enabled_mode
    for pair, modes in enumerate([("disabled", enabled), (enabled, "disabled"), ("disabled", enabled)], 1):
        for mode in modes:
            name = f"pair-{pair}-{mode}"
            capture = output / f"{name}.etf"
            env = {key: value for key, value in os.environ.items() if not key.startswith("BYLAW_")}
            env.update(BYLAW_OVERHEAD_MODE=mode, BYLAW_OVERHEAD_OUTPUT=str(capture))
            command = ["elixir"]
            if mode != "disabled":
                env.update(BYLAW_CONTRACT_APPS=app, BYLAW_OVERHEAD_EBIN=str(ebin))
                command += ["-pa", str(ebin)]
            command += ["-r", str(scripts / "overhead-capture.exs"), "-S", "mix", "test"]
            command += args.selection
            command += ["--seed", str(args.seed), "--max-cases", str(args.max_cases)]
            command += ["--formatter", "ExUnit.CLIFormatter", "--formatter", "BylawOverheadCapture"]
            started = time.monotonic()
            timed_out = False
            with (output / f"{name}.log").open("x") as log:
                child = subprocess.Popen(["/usr/bin/time", "-l", *command], cwd=repo, env=env,
                                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = child.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    code = child.wait()
            row = dict(pair=pair, mode=mode, revision=pin, command=command, exit_code=code,
                       elapsed=time.monotonic() - started, timed_out=timed_out,
                       log=str(output / f"{name}.log"), capture=str(capture))
            log_text = (output / f"{name}.log").read_text()
            for field, label in [("reported_max_rss_bytes", "maximum resident set size"),
                                 ("reported_peak_footprint_bytes", "peak memory footprint")]:
                match = re.search(r"(\d+)\s+" + label, log_text)
                row[field] = int(match[1]) if match else None
            validation = subprocess.run(["elixir", str(scripts / "overhead-result.exs"),
                                         str(capture), mode], capture_output=True, text=True)
            row["capture_valid"] = validation.returncode == 0
            if row["capture_valid"]:
                row["result"] = json.loads(validation.stdout)
            else:
                row["capture_error"] = validation.stderr
            rows.append(row)
            (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
            print(json.dumps(row), flush=True)
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=repo, text=True)
    (output / "checkout-status.txt").write_text(dirty)
    return int(bool(dirty) or any(r["timed_out"] or r["exit_code"] != 0 or not r["capture_valid"] for r in rows))


if __name__ == "__main__":
    raise SystemExit(main())
