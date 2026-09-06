import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
source = Path(__file__).resolve().parents[2] / 'qa/run-performance-phases.py'
spec = importlib.util.spec_from_file_location('phase_runner', source)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ProcessMetricsTest(unittest.TestCase):
    def test_missing_native_time(self):
        original_popen = subprocess.Popen

        def launch(command, *args, **kwargs):
            if command[0] == '/usr/bin/time':
                raise FileNotFoundError('native time is not installed')
            return original_popen(command, *args, **kwargs)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch('shutil.which', return_value=None), patch.object(subprocess, 'Popen', side_effect=launch):
                result = runner.run([sys.executable, '-c', 'print("workload-ran")'], root,
                                    os.environ.copy(), root / 'success.log', 2, 512)
                self.assertEqual(result['exit_code'], 0)
                self.assertIn('workload-ran', (root / 'success.log').read_text())
                self.assertIsNone(result['reported_real_s'])
                self.assertIsNone(result['cpu_s'])
                self.assertIsNone(result['reported_max_rss_bytes'])
                stopped = runner.run([sys.executable, '-c', 'import time; time.sleep(5)'], root,
                                     os.environ.copy(), root / 'deadline.log', .02, 512)
                self.assertEqual(stopped['cutoff'], 'deadline')
                self.assertNotEqual(stopped['exit_code'], 0)
                self.assertLess(stopped['elapsed_s'], 2)

    def test_linux_native_format(self):
        original_popen = subprocess.Popen
        native_commands = []

        def launch(command, *args, **kwargs):
            if command[0] == '/usr/bin/time':
                native_commands.append(command)
                self.assertNotIn('-l', command)
                self.assertEqual(command[1], '-f')
                for token in ['%e', '%U', '%S', '%M']:
                    self.assertIn(token, command[2])
                output = command[2].replace('%e', '0.50').replace('%U', '0.10').replace('%S', '0.20').replace('%M', '1024')
                script = 'import subprocess,sys; result=subprocess.run(sys.argv[2:]); print(sys.argv[1], file=sys.stderr); sys.exit(result.returncode)'
                command = [sys.executable, '-c', script, output, *command[3:]]
            return original_popen(command, *args, **kwargs)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch('sys.platform', 'linux'), patch('shutil.which', return_value='/usr/bin/time'), patch.object(subprocess, 'Popen', side_effect=launch):
                result = runner.run([sys.executable, '-c', 'raise SystemExit(7)'], root,
                                    os.environ.copy(), root / 'linux.log', 2, 512)
                self.assertEqual(len(native_commands), 1)
                self.assertEqual(result['exit_code'], 7)
                self.assertEqual(result['reported_real_s'], .5)
                self.assertAlmostEqual(result['cpu_s'], .3)
                self.assertEqual(result['reported_max_rss_bytes'], 1024 * 1024)


if __name__ == '__main__':
    unittest.main()
