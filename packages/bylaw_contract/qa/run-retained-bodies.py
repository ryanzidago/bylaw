#!/usr/bin/env python3
"""Paired retained-body preparation and native QA; caller supplies immutable builds."""
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
parser.add_argument('kind', choices=['prepare', 'native', 'diagnostic'])
parser.add_argument('baseline', type=Path)
parser.add_argument('candidate', type=Path)
parser.add_argument('fixtures', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--ecto', type=Path, required=True)
parser.add_argument('--livebook', type=Path, required=True)
parser.add_argument('--baseline-source', type=Path, required=True)
parser.add_argument('--trials', type=int, default=3)
args = parser.parse_args()
for field in ["baseline","candidate","fixtures","ecto","livebook","baseline_source"]:
    setattr(args,field,getattr(args,field).resolve(strict=True))
assert args.trials > 0
output = args.output.resolve();output.mkdir(parents=True, exist_ok=False)
variants = {key:getattr(args,key).resolve(strict=True) for key in ['baseline','candidate']}
repos = {key:getattr(args,key).resolve(strict=True) for key in ['ecto','livebook']}
for key,repo in repos.items():
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip() == phases.PINS[key]
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)

sources = list((package/'lib').rglob('*.ex')) + list(qa.glob('retained-body-*.exs')) + [Path(__file__).resolve(),qa/'preparation-overlap.exs',qa/'overhead-capture.exs',qa/'overhead-result.exs',qa/'run-performance-phases.py',qa/'memory-watchdog.py',args.baseline_source]
for ebin in variants.values(): sources += sorted(ebin.glob('*.beam'))
sources += sorted(args.fixtures.rglob('*.ex')) + sorted(args.fixtures.rglob('*.beam'))
def hashes(): return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
source_hashes = hashes()
configs = [(1,8),(1,64),(1,512),(1,4096),(4,512),(16,512),(64,512)]
cases = [(f'modules{n}-body{size}','fixture',n,size,[]) for n,size in configs]
cases += [(key,key,None,None,[]) for key in ['ecto','livebook']]
if args.kind == 'diagnostic': cases = [cases[6],cases[8]]
if args.kind == 'native': cases = [('ecto-full','ecto',None,None,[]),('livebook-isolated','livebook',None,None,['test/livebook/runtime/erl_dist/node_manager_test.exs:8']),('livebook-full','livebook',None,None,[])]
planned = [(trial,case,variant) for trial in range(1,args.trials+1) for case in cases for variant in (['baseline','candidate'] if trial%2 else ['candidate','baseline'])]
manifest = dict(args=vars(args),planned=planned,source_sha256=source_hashes,runtime=subprocess.check_output(['elixir','--version'],text=True),pins=phases.PINS,timeout_s=120,rss_limit_mib=1536,footprint_limit_mib=1536,sample_interval_s=.1)
(output/'manifest.json').write_text(json.dumps(manifest,default=str,indent=2)+'\n')
proc = None
if sys.platform == 'darwin':
    proc = ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
    proc.proc_pid_rusage.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_void_p]
    proc.proc_pid_rusage.restype=ctypes.c_int
watch = {}
def memory_sample(root):
    records=[tuple(map(int,line.split())) for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines() if line.strip()]
    owned={root}
    while True:
        expanded=owned|{pid for pid,ppid,_ in records if ppid in owned}
        if expanded==owned:break
        owned=expanded
    rss=sum(kib*1024 for pid,_,kib in records if pid in owned)
    if proc:
        footprint=0
        for pid in owned:
            value=watchdog.RusageInfoV2()
            if proc.proc_pid_rusage(pid,2,ctypes.byref(value))==0:footprint+=value.phys_footprint
        watch['peak_footprint_bytes']=max(watch.get('peak_footprint_bytes',0),footprint)
        if footprint>1536*2**20:
            watch['footprint_cutoff']=True
            try:os.killpg(root,signal.SIGKILL)
            except ProcessLookupError:pass
    return rss
phases.tree_rss=memory_sample
rows=[]
for trial,case,variant in planned:
    assert hashes()==source_hashes
    name,project,count,body,selection=case
    label=f'{trial}-{name}-{variant}'
    env={k:v for k,v in os.environ.items() if not k.startswith('BYLAW_') and k!='MIX_TEST_PARTITION'}
    env['MIX_ENV']='test'
    ebin=variants[variant]
    capture=output/(label+('.etf' if args.kind=='native' else '.json'))
    command=['elixir','-pa',str(ebin)]
    cwd=repos.get(project,package)
    if args.kind=='native':
        audit=output/(label+'-audit.json')
        env.update(BYLAW_OVERHEAD_EBIN=str(ebin),BYLAW_OVERHEAD_OUTPUT=str(capture),BYLAW_CONTRACT_APPS=phases.APPS[project],BYLAW_PREPARATION_LAYOUT='normal',BYLAW_PREPARATION_SCENARIO='normal',BYLAW_PREPARATION_OUTPUT=str(audit))
        temporary=output/(label+'-tmp');temporary.mkdir()
        env.update(TMPDIR=str(temporary),TMP=str(temporary),TEMP=str(temporary))
        command+=['-r',str(qa/'preparation-overlap.exs'),'-S','mix','test',*selection,'--seed','922331','--max-cases','4','--formatter','ExUnit.CLIFormatter','--formatter','BylawPreparationCapture']
    else:
        env.update(BYLAW_BODY_EBIN=str(ebin),BYLAW_BODY_OUTPUT=str(capture))
        if project=='fixture':
            env['BYLAW_BODY_MODULE_COUNT']=str(count)
            command+=['-pa',str(args.fixtures/f'modules{count}-body{body}'/'ebin')]
        else:env['BYLAW_BODY_APP']=phases.APPS[project]
        if args.kind=='diagnostic':
            env['BYLAW_BODY_SOURCE']=str(args.baseline_source if variant=='baseline' else package/'lib/bylaw/contract/structural_coverage.ex')
            env['BYLAW_BODY_DIAGNOSTIC']=str(output/(label+'-phases.json'))
            command+=['-r',str(qa/'retained-body-diagnostic.exs')]
        if project!='fixture':command+=['-S','mix','run','--no-compile','--no-start']
        command+=[str(qa/'retained-body-probe.exs')]
    watch={}
    metrics=phases.run(command,cwd,env,output/(label+'.log'),120,1536)
    metrics.update(watch)
    row=dict(trial=trial,case=name,variant=variant,command=command,cwd=str(cwd),capture=str(capture),**metrics)
    if capture.exists():
        if args.kind=='native':
            decode=subprocess.run(['elixir',str(qa/'overhead-result.exs'),str(capture),'defaults'],capture_output=True,text=True,timeout=120)
            row['decode_exit']=decode.returncode
            row['result']=json.loads(decode.stdout) if decode.returncode==0 else decode.stderr
            row['audit']=json.loads(audit.read_text()) if audit.exists() else None
        else:row['result']=json.loads(capture.read_text())
    row['source_unchanged']=hashes()==source_hashes
    rows.append(row);(output/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(label,metrics['exit_code'],round(metrics['elapsed_s'],3),flush=True)
for repo in repos.values():assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)
raise SystemExit(int(any(row['exit_code'] or row.get('footprint_cutoff') or not row['source_unchanged'] or 'result' not in row or row.get('decode_exit',0) for row in rows)))
