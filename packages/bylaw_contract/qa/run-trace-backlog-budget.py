#!/usr/bin/env python3
"""Serial matrix: BASE_EBIN CANDIDATE_EBIN NEW_OUTPUT_DIRECTORY (run under mise exec)."""
import json
import subprocess
import sys
from pathlib import Path

baseline, candidate, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
qa = Path(__file__).resolve().parent
variants = [("baseline", baseline.resolve(), 0), ("candidate-low", candidate.resolve(), 64),
            ("candidate-high", candidate.resolve(), 4096)]
manifest = dict(repeats=3, modes=["typespec", "structural", "default"],
                speeds=["running", "paused", "slow10"], calls=1000, payload=2048, cycles=3,
                limit_mib=384, variants={name: limit for name, _, limit in variants})
(output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
for repeat in range(1, 4):
    for mode in manifest["modes"]:
        for speed in manifest["speeds"]:
            for variant, ebin, limit in variants:
                name = f"{mode}--{speed}--{variant}--{repeat}"
                command = ["python3", str(qa / "memory-watchdog.py"), str(output / f"{name}.os.json"),
                           "384", "elixir", "-pa", str(ebin), str(qa / "trace-backlog-budget.exs"),
                           mode, speed, str(limit), str(output / f"{name}.etf")]
                with (output / f"{name}.jsonl").open("w") as log:
                    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
                print(name, result.returncode, flush=True)
                if result.returncode:
                    raise SystemExit(result.returncode)
