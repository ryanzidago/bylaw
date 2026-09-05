#!/usr/bin/env python3
"""Serial Linux Sprite full-suite controls; retain every log and terminal capture."""
import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import time

root, package, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
qa = package / 'qa/diff_scope'
ebin = package / '_build/test/lib/bylaw_contract/ebin'
projects = [
    ('ecto', '11784f821a1bb0eedeee59583e311d836cb39ee1', 'HEAD^'),
    ('phoenix', '1e6183e9ebab9994cf6e43d3af445f32664cc10c', 'f267e8b8c^'),
    ('flame', '2b124f3ffdede8c1f125ce36b237bef1c50940a3', 'e9384f7^'),
]
rows = []
bylaw_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=package, text=True).strip()
prototype_hashes = {str(p.relative_to(qa)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(qa.glob('*.exs'))}
for project, pin, base in projects:
    repo = root / project
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    assert actual == pin, (project, actual)
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo), project
    for round_number, modes in enumerate([['disabled', 'full', 'diff'], ['diff', 'full', 'disabled']], 1):
        for mode in modes:
            name = f'{project}-{round_number}-{mode}'
            capture = output / f'{name}.etf'
            env = {k: v for k, v in os.environ.items() if not k.startswith('BYLAW_')}
            env.update(BYLAW_DIFF_EBIN=str(ebin), BYLAW_DIFF_MODE=mode,
                       BYLAW_DIFF_OUTPUT=str(capture), BYLAW_CONTRACT_APPS=project,
                       BYLAW_CONTRACT_DIFF_BASE=base)
            command = ['elixir', '-r', str(qa / 'formatter.exs'), '-S', 'mix', 'test',
                       '--seed', '922331', '--max-cases', '28', '--no-color',
                       '--formatter', 'ExUnit.CLIFormatter', '--formatter', 'BylawDiffScope.Formatter']
            rss = output / f'{name}.rss'
            start = time.monotonic()
            with (output / f'{name}.log').open('w') as log:
                process = subprocess.run(['/usr/bin/time', '-f', '%M', '-o', str(rss), *command], cwd=repo,
                                         env=env, stdout=log, stderr=subprocess.STDOUT)
            command_elapsed = time.monotonic() - start
            validation = subprocess.run(['elixir', str(qa / 'result.exs'), str(capture)], env=env,
                                        capture_output=True, text=True)
            row = dict(project=project, pin=pin, base=base, round=round_number, mode=mode,
                       command=command, exit_code=process.returncode, elapsed_s=command_elapsed, bylaw_revision=bylaw_revision, prototype_hashes=prototype_hashes,
                       capture_valid=validation.returncode == 0, max_rss_kib=rss.read_text().strip())
            if validation.returncode == 0:
                row['result'] = json.loads(validation.stdout)
            else:
                row['capture_error'] = validation.stderr
            rows.append(row)
            (output / 'results.json').write_text(json.dumps(rows, indent=2)+'\n')
            print(json.dumps({k: v for k, v in row.items() if k not in ['result', 'command']}), flush=True)
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo), project

raise SystemExit(int(any(
    row['exit_code'] != 0 or not row['capture_valid']
    or not row.get('result', {}).get('complete', False)
    or not row.get('result', {}).get('stopped', False)
    or row.get('result', {}).get('failed', 1) != 0
    for row in rows)))
