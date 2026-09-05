"""Build and run the isolated native transport experiment, outside Mix builds."""
import os
from pathlib import Path
import platform
import subprocess
import sys

source = Path(__file__).resolve().parent
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=False)
otp = subprocess.check_output(
    ['elixir', '-e', 'IO.puts(:code.root_dir())'], text=True).strip()
command = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra',
           '-Wno-unused-parameter', '-Werror', '-fPIC', '-shared']
if platform.system() == 'Darwin':
    command.extend(['-undefined', 'dynamic_lookup'])
command.extend(['-I', str(Path(otp) / 'usr/include'), str(source / 'native.c'),
                '-o', str(output / 'native.so')])
with (output / 'compile.log').open('w') as log:
    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
env = dict(os.environ, BYLAW_PRODUCER_NIF=str(output / 'native'))
with (output / 'tests.log').open('w') as log:
    completed = subprocess.run(
        ['elixir', '-r', str(source / 'native.exs'), str(source / 'acceptance.exs')],
        env=env, stdout=log, stderr=subprocess.STDOUT, timeout=35)
print((output / 'tests.log').read_text())
raise SystemExit(completed.returncode)
