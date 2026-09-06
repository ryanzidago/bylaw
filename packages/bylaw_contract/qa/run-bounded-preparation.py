#!/usr/bin/env python3
"""Bounded serial structural-preparation experiment; each unit remains active."""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
qa = Path(__file__).resolve().parent
package = qa.parent

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

phases = module('phases', qa/'run-performance-phases.py')
watchdog = module('watchdog', qa/'memory-watchdog.py')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('kind', choices=['prepare','native','diagnostic'])
parser.add_argument('ebin', type=Path)
parser.add_argument('fixtures', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--ecto', type=Path, required=True)
parser.add_argument('--livebook', type=Path, required=True)
parser.add_argument('--trials', type=int, default=3)
parser.add_argument('--variants', nargs='+', choices=['aggregate','16','64'], default=['aggregate','16','64'])
parser.add_argument('--case', action='append', dest='cases')
args = parser.parse_args()
for key in ['ebin','fixtures','ecto','livebook']:
    setattr(args,key,getattr(args,key).resolve(strict=True))
assert args.trials > 0 and len(set(args.variants)) == len(args.variants)
output = args.output.resolve(); output.mkdir(parents=True,exist_ok=False)
repos = {key:getattr(args,key) for key in ['ecto','livebook']}
for key,repo in repos.items():
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip() == phases.PINS[key]
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)

configs = sorted(args.fixtures.glob('*/config.json'))
cases = [(p.parent.name,'fixture',p,[]) for p in configs] + [(key,key,None,[]) for key in repos]
if args.kind == 'native':
    cases = [('ecto-full','ecto',None,[]),('livebook-isolated','livebook',None,['test/livebook/runtime/erl_dist/node_manager_test.exs:8']),('livebook-full','livebook',None,[])]
if args.kind == 'diagnostic':
    cases = [c for c in cases if c[0] in ['m64-f1-c3-g0','ecto','livebook']]
if args.cases:
    assert set(args.cases) <= {c[0] for c in cases}
    cases = [c for c in cases if c[0] in args.cases]
assert cases
planned=[]
for trial in range(1,args.trials+1):
    offset=(trial-1)%len(args.variants)
    order=args.variants[offset:]+args.variants[:offset]
    planned += [(trial,case,variant) for case in cases for variant in order]
sources = list((package/'lib').rglob('*.ex')) + list(qa.glob('bounded-preparation*.exs'))
sources += [Path(__file__).resolve(),qa/'preparation-overlap.exs',qa/'performance-phase-probe.exs',qa/'run-performance-phases.py',qa/'memory-watchdog.py']
sources += sorted(args.ebin.glob('*.beam')) + sorted(args.fixtures.rglob('*.ex')) + sorted(args.fixtures.rglob('*.beam')) + configs
def hashes(): return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
initial_hashes = hashes()
manifest={'args':vars(args),'planned':planned,'source_sha256':initial_hashes,'pins':phases.PINS,'runtime':subprocess.check_output(['elixir','--version'],text=True),'timeout_s':120,'rss_limit_mib':1536,'footprint_limit_mib':1536,'sample_interval_s':.1,'direct_cycles':['first','repeated'],'diagnostic_compiler_options':'[time]' if args.kind=='diagnostic' else None}
manifest['library_revision']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=package,text=True).strip()
(output/'manifest.json').write_text(json.dumps(manifest,default=str,indent=2)+'\n')
proc=None
if sys.platform=='darwin':
    proc=ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
    proc.proc_pid_rusage.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_void_p]
    proc.proc_pid_rusage.restype=ctypes.c_int
watch={}
def sample(root):
    records=[tuple(map(int,line.split())) for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines() if line.strip()]
    owned={root}
    while True:
        expanded=owned|{pid for pid,ppid,_ in records if ppid in owned}
        if expanded==owned:break
        owned=expanded
    if proc:
        footprint=0
        for pid in owned:
            usage=watchdog.RusageInfoV2()
            if proc.proc_pid_rusage(pid,2,ctypes.byref(usage))==0:footprint+=usage.phys_footprint
        watch['peak_footprint_bytes']=max(watch.get('peak_footprint_bytes',0),footprint)
        if footprint>1536*2**20:
            watch['footprint_cutoff']=True
            try:os.killpg(root,signal.SIGKILL)
            except ProcessLookupError:pass
    return sum(rss*1024 for pid,_,rss in records if pid in owned)
phases.tree_rss=sample
rows=[]
for trial,case,variant in planned:
    assert hashes()==initial_hashes
    name,project,config,selection=case
    label=f'{trial}-{name}-{variant}'
    native=args.kind=='native'
    capture=output/(label+('.etf' if native else '.json'))
    env={k:v for k,v in os.environ.items() if not k.startswith('BYLAW_') and k not in ['MIX_TEST_PARTITION','ERL_COMPILER_OPTIONS']}
    env.update(MIX_ENV='test',BYLAW_BOUNDED_UNITS=variant,BYLAW_BOUNDED_OUTPUT=str(capture),BYLAW_OVERHEAD_EBIN=str(args.ebin))
    cwd=repos.get(project,package)
    command=['elixir','-pa',str(args.ebin)]
    if args.kind=='diagnostic':
        env.update(BYLAW_PHASE_OUTPUT=str(output/(label+'-phases.json')),BYLAW_QUEUE_OUTPUT=str(output/(label+'-queues.json')),ERL_COMPILER_OPTIONS='[time]')
        command+=['-r',str(qa/'performance-phase-probe.exs')]
    if native:
        env.update(BYLAW_OVERHEAD_OUTPUT=str(capture),BYLAW_CONTRACT_APPS=phases.APPS[project],BYLAW_PREPARATION_LAYOUT='normal',BYLAW_PREPARATION_SCENARIO='normal',BYLAW_PREPARATION_OUTPUT=str(output/(label+'-audit.json')))
        temporary=output/(label+'-tmp');temporary.mkdir()
        env.update(TMPDIR=str(temporary),TMP=str(temporary),TEMP=str(temporary))
        command+=['-r',str(qa/'bounded-preparation-native.exs'),'-S','mix','test',*selection,'--seed','922331','--max-cases','4','--formatter','ExUnit.CLIFormatter','--formatter','BylawPreparationCapture']
    else:
        if config:
            env['BYLAW_BOUNDED_FIXTURE']=str(config)
            command+=['-pa',str(config.parent/'ebin')]
        else:
            env['BYLAW_BOUNDED_APP']=phases.APPS[project]
            command+=['-S','mix','run','--no-compile','--no-start']
        command+=[str(qa/'bounded-preparation-probe.exs')]
    watch={}
    metrics=phases.run(command,cwd,env,output/(label+'.log'),120,1536)
    row={'trial':trial,'case':name,'variant':variant,'command':command,'cwd':str(cwd),'capture':str(capture),**metrics,**watch}
    if capture.exists():
        if native:
            decoded=subprocess.run(['elixir',str(qa/'bounded-preparation-result.exs'),str(capture),variant],capture_output=True,text=True,timeout=120)
            row['decode_exit']=decoded.returncode
            row['result']=json.loads(decoded.stdout) if decoded.returncode==0 else decoded.stderr
            audit=output/(label+'-audit.json')
            row['audit']=json.loads(audit.read_text()) if audit.exists() else None
        else:row['result']=json.loads(capture.read_text())
    row['source_unchanged']=hashes()==initial_hashes
    rows.append(row);(output/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(label,row['exit_code'],round(row['elapsed_s'],3),flush=True)
for repo in repos.values():assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)
raise SystemExit(int(any(r['exit_code'] or r['cutoff'] or r.get('footprint_cutoff') or not r['source_unchanged'] or 'result' not in r or r.get('decode_exit',0) for r in rows)))
