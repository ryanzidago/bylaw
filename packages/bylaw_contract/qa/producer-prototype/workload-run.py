"""Run a bounded, serial, fresh-VM comparison; preserve every failure."""
import itertools
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

source = Path(__file__).resolve().parent
root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=False)
env = os.environ.copy()
env['BYLAW_PRODUCER_EBIN'] = str(Path(env['BYLAW_PRODUCER_EBIN']).resolve())
rows = []
settings = itertools.product([1024, 8192], [16, 256], ['burst', 'paced'], [1, 8], ['baseline', 'native', 'trace'])
for index, (total, size, pacing, producers, mode) in enumerate(settings):
    name = f'{index:03}-{mode}-{producers}-{total}-{size}-{pacing}'
    output = root / (name + '.json')
    command = ['elixir', '-r', str(source / 'native.exs'), str(source / 'list-workload.exs'),
               mode, str(producers), str(total), str(size), pacing,
               str(root / 'fixture'), str(output)]
    peak = 0
    reason = None
    started = time.monotonic()
    with (root / (name + '.log')).open('x') as log:
        proc = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while proc.poll() is None:
                rss = subprocess.run(['ps', '-o', 'rss=', '-p', str(proc.pid)], text=True, capture_output=True)
                if rss.stdout.strip():
                    peak = max(peak, int(rss.stdout.strip()))
                if peak > 384 * 1024:
                    reason = 'sampled_rss_budget'
                if time.monotonic() - started > 35:
                    reason = 'wall_timeout'
                if reason:
                    os.killpg(proc.pid, signal.SIGKILL)
                    break
                time.sleep(0.1)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        code = proc.wait()
    row = dict(name=name, exit_code=code, watchdog=reason, peak_rss_kib=peak,
               wall_s=time.monotonic()-started)
    if output.exists():
        row['result'] = json.loads(output.read_text())
    rows.append(row)
    (root / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
    print(json.dumps(dict(name=name, exit_code=code, watchdog=reason,
                         status=row.get('result', {}).get('status'))), flush=True)
if any(row['exit_code'] != 0 or row['watchdog'] or 'result' not in row for row in rows):
    raise SystemExit('Comparison failed: inspect retained logs/results')
