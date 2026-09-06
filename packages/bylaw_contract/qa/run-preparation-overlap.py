#!/usr/bin/env python3
"""Compare ordinary preparation/loading overlap with an explicit QA require gate."""
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
parser.add_argument('project', choices=phases.APPS)
parser.add_argument('repo', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--trials', type=int, default=3)
parser.add_argument('--diagnostic', action='store_true')
parser.add_argument('--selection', nargs='*', default=[])
parser.add_argument('--max-requires', type=phases.concurrency, default='default')
parser.add_argument('--max-cases', type=phases.concurrency, default='default')
args = parser.parse_args()
assert args.trials > 0
repo = args.repo.resolve(strict=True)
output = args.output.resolve()
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
if args.project in phases.PINS:
    assert revision == phases.PINS[args.project]
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo)
output.mkdir(parents=True, exist_ok=False)
sources = sorted((package / 'lib').rglob('*.ex')) + [qa / name for name in
    ['preparation-overlap.exs', 'preparation-overlap-result.exs', 'run-preparation-overlap.py',
     'run-performance-phases.py', 'performance-phase-probe.exs']]
def hashes():
    return {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
source_hashes = hashes()
manifest = dict(project=args.project, repo=str(repo), revision=revision,
    bylaw_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=package, text=True).strip(),
    source_sha256=source_hashes, args=vars(args),
    beam_sha256=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((package / '_build/test/lib/bylaw_contract/ebin').glob('*.beam')))).hexdigest(),
    toolchain=subprocess.check_output(['elixir','--version'], text=True),
    memory_scope='100ms sampled simultaneous process tree; phase BEAM snapshots include concurrent work')
(output / 'manifest.json').write_text(json.dumps(manifest, default=str, indent=2) + '\n')
if args.project == 'fixture':
    with (output / 'warmup.log').open('x') as log:
        subprocess.run(['mix','compile'],cwd=repo,env=dict(os.environ,MIX_ENV='test'),stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
rows = []
expected_inventory = None
for trial in range(1, args.trials+1):
    for layout in (['normal','serialized'] if trial % 2 else ['serialized','normal']):
        assert hashes() == source_hashes
        name = f'{trial}-{layout}'
        capture = output / f'{name}.etf'
        audit = output / f'{name}.json'
        env = {k:v for k,v in os.environ.items() if not k.startswith('BYLAW_')}
        env.update(MIX_ENV='test',BYLAW_PREPARATION_LAYOUT=layout,BYLAW_PREPARATION_SCENARIO='normal',
            BYLAW_PREPARATION_OUTPUT=str(audit),BYLAW_OVERHEAD_OUTPUT=str(capture),
            BYLAW_OVERHEAD_EBIN=str(package / '_build/test/lib/bylaw_contract/ebin'),BYLAW_CONTRACT_APPS=phases.APPS[args.project])
        command = ['elixir','-pa',env['BYLAW_OVERHEAD_EBIN']]
        if args.diagnostic:
            env.update(BYLAW_PHASE_OUTPUT=str(output / f'{name}-spans.json'),BYLAW_QUEUE_OUTPUT=str(output / f'{name}-queues.json'))
            command += ['-r',str(qa/'performance-phase-probe.exs')]
        command += ['-r',str(qa/'preparation-overlap.exs'),'-S','mix','test',*args.selection,
            '--seed','922331','--formatter','ExUnit.CLIFormatter','--formatter','BylawPreparationCapture']
        for flag,value in [('--max-requires',args.max_requires),('--max-cases',args.max_cases)]:
            if value != 'default': command += [flag,str(value)]
        metrics = phases.run(command,repo,env,output / f'{name}.log',120,1536)
        decoded = subprocess.run(['elixir',str(qa/'preparation-overlap-result.exs'),str(capture),'defaults'],capture_output=True,text=True)
        result = None
        if decoded.returncode == 0:
            summary, extra = [json.loads(line) for line in decoded.stdout.splitlines()]
            result = {**summary,**extra}
            inventory = sorted(tuple(t) for t in result['test_identities'])
            if expected_inventory is None: expected_inventory = inventory
        else: inventory = []
        row = dict(trial=trial,layout=layout,command=command,**metrics,result=result,
            capture_valid=decoded.returncode == 0,decode_error=decoded.stderr if decoded.returncode else None,
            matching_inventory=inventory == expected_inventory,
            audit=json.loads(audit.read_text()) if audit.exists() else None,source_unchanged=hashes()==source_hashes)
        rows.append(row)
        (output/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
        print(name,metrics['exit_code'],metrics['reported_real_s'],result and result['coverage_status'],flush=True)
if args.project in phases.PINS:
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)
raise SystemExit(int(any(r['exit_code'] or not r['capture_valid'] or not r['matching_inventory'] or
    not r['source_unchanged'] or not r['audit'] or not r['audit']['cleanup']['clean'] for r in rows)))
