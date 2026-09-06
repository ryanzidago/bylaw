#!/usr/bin/env python3
"""Compare unchanged and grouped case declarations in two owned linked worktrees."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
qa = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('phases', qa / 'run-performance-phases.py')
phases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phases)


def manifest(package):
    def digest(files, normalize=False):
        result = {}
        for path in files:
            data = path.read_bytes()
            if normalize:
                data = re.sub(rb'^  use ExUnit.Case[^\n]*$', b'  use ExUnit.Case', data, count=1, flags=re.MULTILINE)
            result[str(path.relative_to(package))] = hashlib.sha256(data).hexdigest()
        return result

    return dict(
        revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=package, text=True).strip(),
        branch=subprocess.check_output(['git', 'branch', '--show-current'], cwd=package, text=True).strip(),
        library=digest(sorted((package / 'lib').rglob('*.ex'))),
        tests=digest(sorted((package / 'test').rglob('*.ex*'))),
        test_bodies=digest(sorted((package / 'test').rglob('*.ex*')), normalize=True),
        capture_sha256=hashlib.sha256((package / 'qa/grouped-suite-capture.exs').read_bytes()).hexdigest(),
    )


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline', type=Path, help='baseline packages/bylaw_contract directory')
parser.add_argument('candidate', type=Path, help='candidate packages/bylaw_contract directory')
parser.add_argument('output', type=Path)
parser.add_argument('--seeds', nargs='+', type=int, default=[922331, 922331, 922331, 31, 173, 9001])
args = parser.parse_args()
packages = dict(baseline=args.baseline.resolve(), candidate=args.candidate.resolve())
manifests = {name: manifest(path) for name, path in packages.items()}
assert all(m['branch'] not in ['main', 'master', ''] for m in manifests.values())
for field in ['library', 'test_bodies', 'capture_sha256']:
    assert manifests['baseline'][field] == manifests['candidate'][field], field
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
toolchain = subprocess.check_output(['elixir', '--version'], text=True)
(output / 'manifest.json').write_text(json.dumps(dict(packages={k: str(v) for k, v in packages.items()},
    sources=manifests, toolchain=toolchain, seeds=args.seeds,
    runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()), indent=2) + '\n')
rows = []
expected_tests = None
for trial, seed in enumerate(args.seeds, 1):
    order = ['baseline', 'candidate'] if trial % 2 else ['candidate', 'baseline']
    for layout in order:
        package = packages[layout]
        assert manifest(package) == manifests[layout], 'source changed during comparison'
        directory = output / f'{trial}-{layout}'
        directory.mkdir()
        temporary = directory / 'temporary'
        temporary.mkdir()
        env = os.environ.copy()
        env['TMPDIR'] = str(temporary) + '/'
        env['BYLAW_GROUPED_OUTPUT'] = str(directory / 'capture.json')
        command = ['elixir', '-r', 'qa/grouped-suite-capture.exs', '-S', 'mix', 'test',
                   '--seed', str(seed), '--formatter', 'ExUnit.CLIFormatter',
                   '--formatter', 'BylawGroupedSuiteCapture']
        metrics = phases.run(command, package, env, directory / 'run.log', 180, 1536)
        path = directory / 'capture.json'
        capture = json.loads(path.read_text()) if path.exists() else None
        inventory = sorted((t['module'], t['name'], t['line']) for t in capture.get('tests', [])) if capture else []
        if expected_tests is None and inventory:
            expected_tests = inventory
        row = dict(trial=trial, layout=layout, seed=seed, command=command, **metrics,
                   capture=capture, matching_test_inventory=inventory == expected_tests,
                   temporary_paths=sorted(str(p.relative_to(temporary)) for p in temporary.rglob('*')),
                   source_unchanged=manifest(package) == manifests[layout])
        rows.append(row)
        (output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
        print(trial, layout, metrics['exit_code'], metrics['reported_real_s'], flush=True)
raise SystemExit(int(any(r['exit_code'] or not r['matching_test_inventory'] or not r['source_unchanged'] for r in rows)))
