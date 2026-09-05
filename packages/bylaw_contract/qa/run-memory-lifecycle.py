#!/usr/bin/env python3
"""Serial bounded matrix: run under mise exec; arguments are EBIN OUTPUT_DIRECTORY [--returns]."""
import json
import subprocess
import sys
from pathlib import Path

if len(sys.argv) not in [3, 4] or (len(sys.argv) == 4 and sys.argv[3] != "--returns"):
    raise SystemExit(__doc__)

qa = Path(__file__).resolve().parent
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
ebin = str(Path(sys.argv[1]).resolve())
returns = len(sys.argv) == 4 and sys.argv[3] == "--returns"
base = dict(modules=1, functions=1, depth=0, payload=2048 if returns else 256, producers=1, speed="running")
cases = {"base": base}
axes = dict(speed=["slow2", "slow10", "paused"]) if returns else dict(modules=[4, 16], functions=[4, 16], depth=[4, 12], payload=[0, 2048], producers=[2, 4], speed=["slow2", "slow10", "paused"])
for axis, values in axes.items():
    for value in values:
        cases[f"{axis}-{value}"] = dict(base, **{axis: value})
manifest = dict(repeats=3, calls_per_cycle=1000, cycles=3, limit_mib=384,
                modes=["baseline", "typespec", "structural", "default"], return_payload=returns, cases=cases)
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
for repeat in range(1, 4):
    for case, options in cases.items():
        for mode in manifest["modes"]:
            name = f"{case}--{mode}--{repeat}"
            command = ["python3", str(qa / "memory-watchdog.py"), str(out / f"{name}.os.json"), "384",
                       "elixir", "-pa", ebin, str(qa / "memory-lifecycle.exs"), mode, options["speed"]]
            command += [str(options[k]) for k in ["modules", "functions", "depth", "payload", "producers"]]
            command += ["1000", "3", str(out / f"{name}.etf")]
            if returns:
                command += ["return_payload"]
            with (out / f"{name}.jsonl").open("w") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            print(name, result.returncode, flush=True)
            if result.returncode:
                raise SystemExit(result.returncode)
