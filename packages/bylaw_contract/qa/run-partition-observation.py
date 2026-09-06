#!/usr/bin/env python3
"""Bounded caller-owned native Mix partitions and strict QA aggregation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
qa = Path(__file__).resolve().parent
package = qa.parent
spec = importlib.util.spec_from_file_location('phases', qa / 'run-performance-phases.py')
phases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phases)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('project', choices=['fixture', 'ecto', 'livebook'])
parser.add_argument('output', type=Path)
parser.add_argument('--repo', type=Path)
parser.add_argument('--trials', type=int, default=3)
parser.add_argument('--iterations', type=int, default=10)
parser.add_argument('--bootstrap', type=int, choices=[0, 1], default=0)
parser.add_argument('--layouts', nargs='+', choices=['single', 'sequential2', 'concurrent2', 'sequential4', 'concurrent4'], default=['single', 'sequential2', 'concurrent2'])
parser.add_argument('--selection', nargs='*', default=[])
args = parser.parse_args()
assert args.trials > 0 and args.iterations > 0 and args.layouts[0] == 'single'
assert args.project == 'fixture' or args.bootstrap == 0
assert args.project != 'livebook' or not any(x.startswith('concurrent') for x in args.layouts), 'Pinned Livebook shares repository-relative log/data paths; this runner does not provide separate repository isolation'
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=package,text=True).strip()
if args.project == 'fixture':
    repo = output / 'fixture'
    repo.mkdir()
    for name in ['lib', 'test', 'mix.exs']:
        source = qa / 'performance_phase_fixture' / name
        if source.is_dir(): shutil.copytree(source, repo / name)
        else: shutil.copy2(source, repo / name)
    for path in (repo / 'test').glob('*_test.exs'):
        text = path.read_text().replace('for _ <- 1..10 do', 'for _ <- 1..String.to_integer(System.fetch_env!("BYLAW_PARTITION_ITERATIONS")) do')
        text = text.replace('classifies twenty sign calls and twenty literal choices', 'classifies the declared sign calls and literal choices')
        path.write_text(text)
    with (output/'warmup.log').open('x') as log:
        subprocess.run(['mix','compile'],cwd=repo,env=dict(os.environ,MIX_ENV='test'),stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
    project_revision = revision
else:
    assert args.repo
    repo = args.repo.resolve(strict=True)
    project_revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
    assert project_revision == phases.PINS[args.project]
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)

sources = sorted((package/'lib').rglob('*.ex')) + [qa/name for name in ['run-partition-observation.py','partition-capture.exs','partition-merge.exs','partition-result.exs','preparation-overlap.exs','run-performance-phases.py']]
if args.project == 'fixture': sources += sorted((repo/'lib').rglob('*.ex')) + sorted((repo/'test').rglob('*.exs')) + [repo/'mix.exs']
beam = package/'_build/test/lib/bylaw_contract/ebin'
def hashes():
    return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + sorted(beam.glob('*.beam'))}
source_hashes = hashes()
runtime = subprocess.check_output(['elixir','--version'],text=True)
fingerprint = hashlib.sha256(json.dumps(dict(sources=source_hashes,project_revision=project_revision,runtime=runtime,iterations=args.iterations,bootstrap=args.bootstrap),sort_keys=True).encode()).hexdigest()
invocation_id = uuid.uuid4().hex
planned = [{'name':f'{trial}-{layout}','run_id':f'{invocation_id}/{trial}-{layout}','layout':layout,'partitions':1 if layout=='single' else int(layout[-1])} for trial in range(1,args.trials+1) for layout in (args.layouts if trial%2 else list(reversed(args.layouts)))]
manifest = dict(invocation_id=invocation_id,args=vars(args),repo=str(repo),bylaw_revision=revision,project_revision=project_revision,runtime=runtime,source_sha256=source_hashes,source_fingerprint=fingerprint,planned=planned,seed=922331,max_cases=4,max_requires="native_default",trace_queue_limit=4096,deadline_s=120,per_vm_rss_mib=1536,aggregate_rss_mib=3072,memory_scope='100ms simultaneous process-tree sum, shared pages may count more than once')
(output/'manifest.json').write_text(json.dumps(manifest,default=str,indent=2)+'\n')

def process_table():
    return [tuple(map(int,line.split())) for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines() if line.strip()]

def descendants(root, records):
    owned={root}
    while True:
        expanded=owned|{pid for pid,ppid,_ in records if ppid in owned}
        if expanded==owned: return owned
        owned=expanded

def native_metrics(text):
    if sys.platform=='darwin':
        rss=re.search(r'(\d+)\s+maximum resident set size',text)
        clock=re.search(r'([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys',text)
        return dict(reported_max_rss_bytes=int(rss[1]) if rss else None,reported_real_s=float(clock[1]) if clock else None,cpu_s=float(clock[2])+float(clock[3]) if clock else None)
    clock=re.search(r'^BYLAW_TIME ([\d.]+) ([\d.]+) ([\d.]+) (\d+)$',text,re.MULTILINE)
    return dict(reported_real_s=float(clock[1]) if clock else None,cpu_s=float(clock[2])+float(clock[3]) if clock else None,reported_max_rss_bytes=int(clock[4])*1024 if clock else None)

def run_group(commands, concurrent):
    start=time.monotonic(); active=[]; next_index=0; peak=0
    try:
        while next_index<len(commands) or active:
            while next_index<len(commands) and (concurrent or not active):
                row=commands[next_index];next_index+=1
                timed=row['command']
                if Path('/usr/bin/time').exists():
                    timed=['/usr/bin/time',*(['-l'] if sys.platform=='darwin' else ['-f','BYLAW_TIME %e %U %S %M']),*timed]
                stream=Path(row['log']).open('x')
                child=subprocess.Popen(timed,cwd=repo,env=row.pop('_env'),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
                active.append((child,stream,row,time.monotonic()))
            records=process_table()
            all_owned=set()
            for child,_,row,began in active:
                owned=descendants(child.pid,records);all_owned|=owned
                rss=sum(kib*1024 for pid,_,kib in records if pid in owned)
                row['sampled_tree_peak_bytes']=max(row['sampled_tree_peak_bytes'],rss)
                reason='deadline' if time.monotonic()-began>120 else 'sampled_tree_rss' if rss>1536*2**20 else None
                if reason and child.poll() is None:
                    row['cutoff']=reason;os.killpg(child.pid,signal.SIGKILL)
            total=sum(kib*1024 for pid,_,kib in records if pid in all_owned);peak=max(peak,total)
            if total>3072*2**20:
                for child,_,row,_ in active:
                    if child.poll() is None:
                        row['cutoff']='aggregate_sampled_rss';os.killpg(child.pid,signal.SIGKILL)
            remaining=[]
            for child,stream,row,began in active:
                if child.poll() is None: remaining.append((child,stream,row,began))
                else:
                    row['exit_code']=child.wait();row['elapsed_s']=time.monotonic()-began;stream.close()
                    row.update(native_metrics(Path(row['log']).read_text()))
            active=remaining
            if active: time.sleep(.1)
    finally:
        for child,stream,row,_ in active:
            if child.poll() is None: os.killpg(child.pid,signal.SIGKILL)
            child.wait();stream.close()
    return time.monotonic()-start,peak

def cpu_usage():
    own=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
    return own.ru_utime+own.ru_stime+children.ru_utime+children.ru_stime

results=[];reference=None
for group in planned:
    assert hashes()==source_hashes
    group_start=time.monotonic();cpu_start=cpu_usage();directory=output/group['name'];directory.mkdir()
    commands=[]
    for partition in range(1,group['partitions']+1):
        name=str(partition);capture=directory/(name+'.etf');audit=directory/(name+'.json')
        temporary=directory/(name+'-tmp');temporary.mkdir()
        env={k:v for k,v in os.environ.items() if not k.startswith('BYLAW_') and k!='MIX_TEST_PARTITION'}
        env.update(MIX_ENV='test',TMPDIR=str(temporary),TMP=str(temporary),TEMP=str(temporary),BYLAW_PREPARATION_LAYOUT='normal',BYLAW_PREPARATION_SCENARIO='normal',BYLAW_PREPARATION_OUTPUT=str(audit),BYLAW_OVERHEAD_OUTPUT=str(capture),BYLAW_OVERHEAD_EBIN=str(beam),BYLAW_CONTRACT_APPS=phases.APPS[args.project],BYLAW_PARTITION_BOOTSTRAP=str(args.bootstrap),BYLAW_PARTITION_ITERATIONS=str(args.iterations),BYLAW_PARTITION_FINGERPRINT=fingerprint,BYLAW_PARTITION_RUN_ID=group['run_id'],BYLAW_PARTITION_TOTAL=str(group['partitions']),BYLAW_PARTITION_FAILURES=str(directory/(name+'-failures')),MIX_TEST_PARTITION=name)
        command=['elixir','-pa',str(beam),'-r',str(qa/'preparation-overlap.exs'),'-r',str(qa/'partition-capture.exs'),'-S','mix','test',*args.selection,'--partitions',str(group['partitions']),'--seed','922331','--max-cases','4','--formatter','ExUnit.CLIFormatter','--formatter','BylawPartitionCapture']
        commands.append(dict(partition_id=partition,command=command,_env=env,capture=str(capture),audit=str(audit),log=str(directory/(name+'.log')),cutoff=None,sampled_tree_peak_bytes=0))
    native_wall,native_peak=run_group(commands,group['layout'].startswith('concurrent'))
    if reference is None: reference=commands[0]
    plan_path=directory/'plan.json'; merged=directory/'merged.etf'; evaluation=directory/'evaluation.json';input_path=directory/'input.json'
    payload=dict(project=args.project,run_id=group['run_id'],source_fingerprint=fingerprint,iterations=args.iterations,bootstrap=args.bootstrap,commands=commands,reference_capture=reference['capture'],reference_audit=reference['audit'],plan=str(plan_path))
    input_path.write_text(json.dumps(payload,indent=2)+'\n')
    evaluation_command=['elixir','-pa',str(beam),str(qa/'partition-result.exs'),str(input_path),str(evaluation),str(merged)]
    post=phases.run(evaluation_command,package,dict(os.environ),directory/'evaluation.log',120,1536)
    decision=json.loads(evaluation.read_text()) if evaluation.exists() else dict(accepted=False,error='postprocessing failed; see evaluation.log')
    native_cpu=sum(row['cpu_s'] for row in commands) if all(row['cpu_s'] is not None for row in commands) else None
    native_and_post_cpu=native_cpu+post['cpu_s'] if native_cpu is not None and post['cpu_s'] is not None else None
    total_cpu=cpu_usage()-cpu_start
    row=dict(**group,commands=commands,plan=str(plan_path),merged_capture=str(merged),native_wall_s=native_wall,wall_s=time.monotonic()-group_start,cpu_s=native_cpu,total_cpu_s=total_cpu,native_and_postprocess_cpu_s=native_and_post_cpu,sampled_native_group_peak_bytes=native_peak,sampled_group_peak_bytes=max(native_peak,post['sampled_tree_peak_bytes']),postprocess=dict(command=evaluation_command,**post),merge=decision,source_unchanged=hashes()==source_hashes)
    results.append(row);(output/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(group['name'],[r['exit_code'] for r in commands],'aggregate',decision['accepted'],round(row['wall_s'],3),flush=True)
if args.project!='fixture': assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo)
raise SystemExit(int(any(not row['source_unchanged'] or row['postprocess']['exit_code'] or any(c['exit_code'] for c in row['commands']) for row in results)))
