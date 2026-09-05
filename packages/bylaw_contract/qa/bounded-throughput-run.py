import itertools,json,os,signal,subprocess,time,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve(); root.mkdir(parents=True, exist_ok=False); (root/'trials').mkdir()
script=Path(__file__).resolve().with_name('bounded-throughput-trial.exs')
env=os.environ.copy();env['BYLAW_LIMIT_EBIN']=str(Path(os.environ['BYLAW_LIMIT_EBIN']).resolve()); env['BYLAW_LIMIT_FIXTURE']=str(root/'fixture')
rows=[]
for index,(mode,producers,total,payload,pacing) in enumerate(itertools.product(['typespec','structural','default'],[1,8],[1024,8192],[('binary',16),('binary',4096),('list',8),('list',256)],['burst','paced'])):
 shape,size=payload;name=f'{index:03}-{mode}-{producers}-{total}-{shape}-{size}-{pacing}'
 output=root/'trials'/(name+'.json');logpath=root/'trials'/(name+'.log')
 command=['elixir',str(script),mode,str(producers),str(total),shape,str(size),pacing,str(output)]
 peak=0;reason=None;started=time.monotonic()
 with logpath.open('x') as log:
  proc=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  while proc.poll() is None:
   rss=subprocess.run(['ps','-o','rss=','-p',str(proc.pid)],text=True,capture_output=True)
   if rss.stdout.strip(): peak=max(peak,int(rss.stdout.strip()))
   if peak>384*1024:reason='sampled_rss_budget'
   if time.monotonic()-started>35:reason='wall_timeout'
   if reason:os.killpg(proc.pid,signal.SIGKILL);break
   time.sleep(.1)
  code=proc.wait()
 row={'name':name,'exit_code':code,'watchdog':reason,'peak_rss_kib':peak,'wall_s':time.monotonic()-started}
 if output.exists():row['result']=json.loads(output.read_text())
 rows.append(row);(root/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
 print(json.dumps({'trial':index,'name':name,'exit_code':code,'watchdog':reason,'status':[c['status'] for c in row.get('result',{}).get('cycles',[])]}),flush=True)
 if code !=0:print(logpath.read_text()[-3000:],flush=True)

if len(rows) != 96 or any(r['exit_code'] != 0 or r['watchdog'] or 'result' not in r for r in rows):
 raise SystemExit('Matrix failed; inspect retained logs and results')
