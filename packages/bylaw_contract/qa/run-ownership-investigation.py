#!/usr/bin/env python3
"""Bounded fresh-VM explicit-root and native-scanning investigation; no caller edits."""
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
package = qa.parent
spec = importlib.util.spec_from_file_location('phases', qa / 'run-performance-phases.py')
phases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phases)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--trials', type=int, default=3)
args = parser.parse_args()
assert args.trials > 0
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
sources = sorted((package / 'lib').rglob('*.ex')) + [qa / n for n in
    ['ownership-probe.exs', 'ownership-adapter.exs', 'run-ownership-investigation.py', 'run-performance-phases.py']]
def hashes():
    return {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
source_hashes = hashes()
manifest = dict(revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=package, text=True).strip(),
    source_sha256=source_hashes, toolchain=subprocess.check_output(['elixir', '--version'], text=True),
    trials=args.trials, max_cases=4, max_trace_queue=4096, seed=922331,
    memory_scope='100ms sampled simultaneous process tree, shared pages may count twice',
    sample_scope='5ms worker queue/memory samples in all modes; scan timing only in diagnostic commands')
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
plans = []
for trial in range(1, args.trials + 1):
    order = ['scan', 'explicit'] if trial % 2 else ['explicit', 'scan']
    for idle in [0, 1000, 5000]:
        for scenario, profile in [('matched', 'plain'), ('immediate', 'plain'), ('matched', 'diagnostic')]:
            plans.extend((trial, mode, scenario, idle, profile) for mode in order)
        plans.append((trial, 'all', 'settled', idle, 'plain'))
plans.extend((1, 'explicit', scenario, 0, 'plain') for scenario in ['failure', 'timeout', 'exhausted'])
(output / 'plan.json').write_text(json.dumps(plans, indent=2) + '\n')
names = ['test root body and recursion', 'test nested tasks retain their own caller identities',
         'test supervised ordinary and pre-existing children keep distinct callers']
expected_inventory = sorted((name, lane) for name in names for lane in range(1, 5))
rows = []
for trial, mode, scenario, idle, profile in plans:
    assert hashes() == source_hashes, 'source changed during investigation'
    name = f'{trial}-{mode}-{scenario}-{idle}-{profile}'
    capture_path = output / f'{name}.json'
    command = ['elixir', '-pa', str(package / '_build/test/lib/bylaw_contract/ebin'),
               str(qa / 'ownership-probe.exs'), mode, scenario, str(capture_path), str(idle), profile]
    metrics = phases.run(command, package, dict(os.environ), output / f'{name}.log', 30, 1536)
    capture = json.loads(capture_path.read_text()) if capture_path.exists() else None
    expected_exit = 1 if scenario in ['failure', 'timeout'] else 0
    valid = capture is not None and metrics['exit_code'] == expected_exit and capture['cleanup']['clean']
    if capture:
        valid &= sorted((t['name'], t['lane']) for t in capture['tests']) == expected_inventory
        if scenario not in ['immediate', 'exhausted']:
            valid &= capture['promised_calls_exact'] and capture['caller_returns_exact']
        if scenario == 'matched':
            valid &= capture['oracle_calls'] == 112 and sum(capture['observed_by_kind'].values()) == 76
        if mode == 'all':
            valid &= capture['all_calls_exact'] and capture['oracle_calls'] == 124
    row = dict(trial=trial, mode=mode, scenario=scenario, idle=idle, profile=profile,
               command=command, **metrics, capture=capture, valid=bool(valid), source_unchanged=hashes() == source_hashes)
    rows.append(row)
    (output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
    print(name, metrics['exit_code'], round(metrics['elapsed_s'], 3), bool(valid), flush=True)
raise SystemExit(int(any(not r['valid'] or not r['source_unchanged'] for r in rows)))
