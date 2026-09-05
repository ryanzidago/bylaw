#!/usr/bin/env python3
"""Run one owned process group with a sampled macOS physical-footprint cutoff.

Usage: memory-watchdog.py OUTPUT.json LIMIT_MIB COMMAND [ARG ...]
This is a sampled cutoff, not a kernel-enforced allocation limit.
"""
import ctypes
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


class RusageInfoV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size "
            "resident_size phys_footprint proc_start_abstime proc_exit_abstime "
            "child_user_time child_system_time child_pkg_idle_wkups child_interrupt_wkups "
            "child_pageins child_elapsed_abstime diskio_bytesread diskio_byteswritten"
        ).split()
    ]


def main():
    if sys.platform != "darwin" or len(sys.argv) < 4:
        raise SystemExit(__doc__)
    output, limit_mib, *command = sys.argv[1:]
    limit = int(limit_mib) * 1024 * 1024
    if not 1 <= int(limit_mib) <= 512:
        raise SystemExit("LIMIT_MIB must be between 1 and 512")
    proc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    proc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    proc.proc_pid_rusage.restype = ctypes.c_int
    started = time.monotonic()
    child = subprocess.Popen(command, start_new_session=True)
    samples = []
    status = "complete"
    try:
        while child.poll() is None:
            usage = RusageInfoV2()
            result = proc.proc_pid_rusage(child.pid, 2, ctypes.byref(usage))
            if result == 0:
                sample = {
                    "seconds": time.monotonic() - started,
                    "wall_us": time.time_ns() // 1000,
                    "footprint": usage.phys_footprint,
                    "resident": usage.resident_size,
                }
                samples.append(sample)
                if usage.phys_footprint > limit:
                    status = "incomplete_os_budget"
                    break
            elif child.poll() is None and time.monotonic() - started > 0.2:
                status = "incomplete_os_sampling_error"
                break
            if time.monotonic() - started > 60:
                status = "incomplete_timeout"
                break
            time.sleep(0.02)
    finally:
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        code = child.wait()
        if status == "complete" and code != 0:
            status = "incomplete_process_exit"
        if not samples:
            status = "incomplete_no_os_samples"
        Path(output).write_text(json.dumps({
            "status": status, "exit_code": code, "limit_bytes": limit,
            "sample_interval_seconds": 0.02, "pid": child.pid,
            "peak_footprint": max((s["footprint"] for s in samples), default=0),
            "samples": samples,
        }, indent=2) + "\n")
    return 0 if status == "complete" else 86


if __name__ == "__main__":
    raise SystemExit(main())
