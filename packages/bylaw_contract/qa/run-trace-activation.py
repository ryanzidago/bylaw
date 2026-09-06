#!/usr/bin/env python3
"""Bounded, serial trace activation controls; diagnostic runs stay separate."""
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
parser.add_argument('kind', choices=['fixture', 'native'])
parser.add_argument('ebin', type=Path)
parser.add_argument('fixtures', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--ecto', type=Path, required=True)
parser.add_argument('--livebook', type=Path, required=True)
parser.add_argument('--trials', type=int, default=3)
parser.add_argument('--diagnostic', action='store_true')
parser.add_argument('--counts', nargs='+', type=int, default=[0,64,256,1024,4096,8192])
parser.add_argument('--modes', nargs='+', choices=['calls','returns','both','mixed'], default=['calls','returns','both','mixed'])
parser.add_argument('--case', action='append', dest='cases')
args = parser.parse_args()
for key in ['ebin','fixtures','ecto','livebook']:
    setattr(args,key,getattr(args,key).resolve(strict=True))
assert args.trials > 0 and args.counts and min(args.counts) >= 0 and max(args.counts) <= 8192
assert len(set(args.counts)) == len(args.counts) and len(set(args.modes)) == len(args.modes)
fixture_config = json.loads((args.fixtures/'config.json').read_text())
assert len(fixture_config['modules']) == 128 and fixture_config['functions'] == 64
output = args.output.resolve(); output.mkdir(parents=True,exist_ok=False)
repos = {key:getattr(args,key) for key in ['ecto','livebook']}
for key,repo in repos.items():
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip() == phases.PINS[key]
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)

cases = [(f'{count}-{mode}',count,mode,None,[]) for count in args.counts for mode in args.modes]
if args.kind == 'native':
    cases = [('ecto-full',None,None,'ecto',[]),('livebook-isolated',None,None,'livebook',['test/livebook/runtime/erl_dist/node_manager_test.exs:8']),('livebook-full',None,None,'livebook',[])]
if args.cases:
    assert set(args.cases) <= {c[0] for c in cases}
    cases = [c for c in cases if c[0] in args.cases]
assert cases
planned=[]
for trial in range(1,args.trials+1):
    offset=((trial-1)*max(1,len(cases)//3))%len(cases)
    planned += [(trial,case) for case in cases[offset:]+cases[:offset]]

sources = list((package/'lib').rglob('*.ex')) + list(qa.glob('trace-activation*.exs'))
sources += [Path(__file__).resolve(),qa/'preparation-overlap.exs',qa/'run-performance-phases.py',qa/'memory-watchdog.py',qa/'bounded-preparation-result.exs']
sources += sorted(args.ebin.glob('*.beam')) + sorted(args.fixtures.rglob('*.ex')) + sorted(args.fixtures.rglob('*.beam')) + [args.fixtures/'config.json']
def hashes(): return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
initial_hashes = hashes()
manifest={'args':vars(args),'planned':planned,'source_sha256':initial_hashes,'pins':phases.PINS,'runtime':subprocess.check_output(['elixir','--version'],text=True),'timeout_s':120,'rss_limit_mib':1536,'footprint_limit_mib':1536,'sample_interval_s':.1,'direct_cycles':['first','repeated'],'fixture_modules_loaded':128,'fixture_functions_loaded':8192,'workload_batch_size':64,'library_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=package,text=True).strip()}
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
for trial,case in planned:
    assert hashes()==initial_hashes
    name,count,mode,project,selection=case
    label=f'{trial}-{name}'
    native=args.kind=='native'
    capture=output/(label+('.etf' if native else '.json'))
    env={k:v for k,v in os.environ.items() if not k.startswith('BYLAW_') and k not in ['MIX_TEST_PARTITION','ERL_COMPILER_OPTIONS']}
    env.update(MIX_ENV='test',BYLAW_OVERHEAD_EBIN=str(args.ebin))
    cwd=repos.get(project,package)
    command=['elixir','-pa',str(args.ebin)]
    if args.diagnostic:
        env['BYLAW_TRACE_PHASE_OUTPUT']=str(output/(label+'-phases.json'))
        command+=['-r',str(qa/'trace-activation-diagnostic.exs')]
    if native:
        env.update(BYLAW_OVERHEAD_OUTPUT=str(capture),BYLAW_CONTRACT_APPS=phases.APPS[project],BYLAW_PREPARATION_LAYOUT='normal',BYLAW_PREPARATION_SCENARIO='normal',BYLAW_PREPARATION_OUTPUT=str(output/(label+'-audit.json')))
        temporary=output/(label+'-tmp');temporary.mkdir()
        env.update(TMPDIR=str(temporary),TMP=str(temporary),TEMP=str(temporary))
        command+=['-r',str(qa/'preparation-overlap.exs'),'-S','mix','test',*selection,'--seed','922331','--max-cases','4','--formatter','ExUnit.CLIFormatter','--formatter','BylawPreparationCapture']
    else:
        env.update(BYLAW_TRACE_FIXTURE=str(args.fixtures/'config.json'),BYLAW_TRACE_COUNT=str(count),BYLAW_TRACE_MODE=mode,BYLAW_TRACE_OUTPUT=str(capture))
        command+=['-pa',str(args.fixtures/'ebin'),str(qa/'trace-activation-probe.exs')]
    watch={}
    metrics=phases.run(command,cwd,env,output/(label+'.log'),120,1536)
    row={'trial':trial,'case':name,'command':command,'cwd':str(cwd),'capture':str(capture),**metrics,**watch}
    if capture.exists():
        if native:
            decoded=subprocess.run(['elixir',str(qa/'bounded-preparation-result.exs'),str(capture),'aggregate'],capture_output=True,text=True,timeout=120)
            row['decode_exit']=decoded.returncode
            row['result']=json.loads(decoded.stdout) if decoded.returncode==0 else decoded.stderr
            audit=output/(label+'-audit.json')
            row['audit']=json.loads(audit.read_text()) if audit.exists() else None
        else:row['result']=json.loads(capture.read_text())
    if args.diagnostic:
        spans=output/(label+'-phases.json')
        row['spans']=json.loads(spans.read_text()) if spans.exists() else None
    row['source_unchanged']=hashes()==initial_hashes
    rows.append(row);(output/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(label,row['exit_code'],round(row['elapsed_s'],3),flush=True)
for repo in repos.values():assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)
raise SystemExit(int(any(r['exit_code'] or r['cutoff'] or r.get('footprint_cutoff') or not r['source_unchanged'] or 'result' not in r or r.get('decode_exit',0) or (args.diagnostic and r.get('spans') is None) for r in rows)))
