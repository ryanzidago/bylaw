#!/usr/bin/env python3
"""Summarize trusted local matrix outputs: MATRIX_DIRECTORY OUTPUT.json."""
import bisect
import json
import sys
from pathlib import Path

root, output = map(Path, sys.argv[1:])
manifest = json.loads((root / "manifest.json").read_text())
results = json.loads((root / "results.json").read_text())
trials = []
for name, result in sorted(results.items()):
    os_result = json.loads((root / f"{name}.os.json").read_text())
    assert os_result["status"] == "complete" and os_result["exit_code"] == 0
    rows = [json.loads(line) for line in (root / f"{name}.jsonl").read_text().splitlines() if line.startswith("{")]
    markers = sorted((row["wall_us"], row["phase"]) for row in rows if "beam" in row)
    times = [pair[0] for pair in markers]
    phases = {}
    for row in rows:
        if "beam" not in row:
            continue
        phase = row["phase"]
        item = phases.setdefault(phase, {})
        if row["beam"]["total"] > item.get("beam_peak", 0):
            item.update(beam_peak=row["beam"]["total"], beam_at_peak=row["beam"], peak_wall_us=row["wall_us"])
        workers = row.get("processes", [])[1:]
        item["max_worker_queue_sum"] = max(item.get("max_worker_queue_sum", 0), sum(p.get("message_queue_len", 0) for p in workers))
        item["max_worker_memory_sum"] = max(item.get("max_worker_memory_sum", 0), sum(p.get("memory", 0) for p in workers))
    for row in os_result["samples"]:
        index = bisect.bisect_right(times, row["wall_us"]) - 1
        phase = markers[index][1] if index >= 0 else "bootstrap"
        item = phases.setdefault(phase, {})
        item["os_footprint_peak"] = max(item.get("os_footprint_peak", 0), row["footprint"])
    trials.append(dict(name=name, config=result["config"], status=os_result["status"],
                       os_footprint_peak=os_result["peak_footprint"], phases=phases,
                       retained=[row for row in rows if "shared_bytes" in row],
                       allocators=[row for row in rows if row.get("kind") == "allocator_cleanup"],
                       cycles=result["cycles"]))
groups = {}
for trial in trials:
    name = trial["name"].rsplit("--", 1)[0]
    group = groups.setdefault(name, dict(config=trial["config"], trials=0, cycles=0,
                                         os_peaks=[], phases={}, retained=trial["retained"],
                                         coverage_hashes=set(), report_hashes=set(), encoded_bytes=[]))
    group["trials"] += 1
    group["cycles"] += len(trial["cycles"])
    group["os_peaks"].append(trial["os_footprint_peak"])
    for cycle in trial["cycles"]:
        if "coverage_hash" in cycle:
            group["coverage_hashes"].add(cycle["coverage_hash"])
            group["report_hashes"].add(cycle["report_hash"])
            group["encoded_bytes"].append(cycle["encoding"]["bytes"])
    for phase, metrics in trial["phases"].items():
        peak = group["phases"].setdefault(phase, {})
        if metrics.get("beam_peak", 0) > peak.get("beam_peak", 0):
            peak.update({key: metrics[key] for key in ["beam_peak", "beam_at_peak", "peak_wall_us"]})
            peak["beam_peak_trial"] = trial["name"]
        for key in ["os_footprint_peak", "max_worker_queue_sum", "max_worker_memory_sum"]:
            if key in metrics:
                peak[key] = max(peak.get(key, 0), metrics[key])
for group in groups.values():
    peaks = group.pop("os_peaks")
    group["os_peak_range"] = [min(peaks), max(peaks)]
    group["coverage_hashes"] = sorted(group["coverage_hashes"])
    group["report_hashes"] = sorted(group["report_hashes"])
    group["encoded_bytes"] = sorted(set(group["encoded_bytes"]))
    group["retained"] = list({json.dumps(row, sort_keys=True): row for row in group["retained"]}.values())
mode_phases = {}
for group in groups.values():
    phases = mode_phases.setdefault(group["config"]["mode"], {})
    for phase, metrics in group.pop("phases").items():
        # Preserve cleanup cycles; combine the other repeated lifecycle phases.
        if phase.rsplit("_", 1)[-1].isdigit() and not phase.startswith("cleanup_"):
            phase = phase.rsplit("_", 1)[0]
        peak = phases.setdefault(phase, {})
        if metrics.get("beam_peak", 0) > peak.get("beam_peak", 0):
            peak.update({key: metrics[key] for key in ["beam_peak", "beam_at_peak", "peak_wall_us", "beam_peak_trial"]})
        for key in ["os_footprint_peak", "max_worker_queue_sum", "max_worker_memory_sum"]:
            if key in metrics:
                peak[key] = max(peak.get(key, 0), metrics[key])
summary = dict(revision="f8cb8ec6852e4e5b6a38cad7b3635ba4813829ed", manifest=manifest,
               phase_attribution="Nearest preceding BEAM phase marker; OS and BEAM peaks are sampled, not hard maxima.",
               complete_trials=len(trials), complete_cycles=sum(len(t["cycles"]) for t in trials),
               groups=groups, mode_phases=mode_phases)
output.write_text(json.dumps(summary, separators=(",", ":")) + "\n")
print("trials", len(trials), "max OS footprint", max(t["os_footprint_peak"] for t in trials))
