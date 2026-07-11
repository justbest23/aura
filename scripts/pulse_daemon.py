#!/usr/bin/env python3
"""Long-running vitals sampler.

Runs continuously (see systemd/aura-pulse.service) and writes a small JSON
state file every ~200ms. The plasmoid just `cat`s that file on a fast timer
instead of forking `python3` + importing psutil on every poll - forking a
fresh interpreter multiple times a second would be the wasteful way to get a
fast update rate; sampling once in a warm long-lived process and letting the
UI read the result is the cheap way.

GPU stats come from `nvidia-smi`, which is comparatively slow to spawn, so
it's only refreshed every GPU_EVERY ticks and the last reading is reused
in between.
"""
import json
import os
import subprocess
import time

import psutil

INTERVAL = 0.2  # 5Hz - "multiple times per second" without hammering the GPU
GPU_EVERY = 5  # refresh nvidia-smi every ~1s
STATE_DIR = os.path.expanduser("~/.cache/aura")
STATE_FILE = os.path.join(STATE_DIR, "stats.json")


def gpu_stats():
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        ).stdout.strip()
        util, temp, mem_used, mem_total = (float(x) for x in out.split(","))
        return util, temp, round(mem_used / mem_total * 100, 1)
    except Exception:
        return None, None, None


def cpu_temp():
    temps = psutil.sensors_temperatures()
    for key in ("coretemp", "k10temp"):
        if key in temps and temps[key]:
            for entry in temps[key]:
                if entry.label in ("Package id 0", "Tctl"):
                    return entry.current
            return temps[key][0].current
    return None


def write_state(state: dict) -> None:
    tmp_path = STATE_FILE + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(state, f)
    os.replace(tmp_path, STATE_FILE)


def main() -> None:
    os.makedirs(STATE_DIR, exist_ok=True)

    psutil.cpu_percent(interval=None)  # first call is meaningless, per psutil docs
    prev_net = psutil.net_io_counters()
    prev_disk = psutil.disk_io_counters()
    prev_t = time.time()
    gpu_pct = gpu_temp = gpu_mem_pct = None

    tick = 0
    while True:
        time.sleep(INTERVAL)
        tick += 1

        now = time.time()
        dt = max(now - prev_t, 0.001)
        prev_t = now

        cpu_pct = psutil.cpu_percent(interval=None)
        freq = psutil.cpu_freq()
        vm = psutil.virtual_memory()

        net = psutil.net_io_counters()
        disk = psutil.disk_io_counters()
        net_rx_kbps = (net.bytes_recv - prev_net.bytes_recv) / 1024 / dt
        net_tx_kbps = (net.bytes_sent - prev_net.bytes_sent) / 1024 / dt
        disk_r_kbps = (disk.read_bytes - prev_disk.read_bytes) / 1024 / dt
        disk_w_kbps = (disk.write_bytes - prev_disk.write_bytes) / 1024 / dt
        prev_net, prev_disk = net, disk

        if tick % GPU_EVERY == 0:
            gpu_pct, gpu_temp, gpu_mem_pct = gpu_stats()

        write_state(
            {
                "cpu_pct": round(cpu_pct, 1),
                "cpu_temp": cpu_temp(),
                "cpu_freq_cur": round(freq.current, 0) if freq else None,
                "cpu_freq_min": round(freq.min, 0) if freq and freq.min else None,
                "cpu_freq_max": round(freq.max, 0) if freq and freq.max else None,
                "ram_pct": round(vm.percent, 1),
                "ram_used_gb": round(vm.used / 1024**3, 1),
                "ram_total_gb": round(vm.total / 1024**3, 1),
                "gpu_pct": gpu_pct,
                "gpu_temp": gpu_temp,
                "gpu_mem_pct": gpu_mem_pct,
                "proc_count": len(psutil.pids()),
                "net_rx_kbps": round(net_rx_kbps, 1),
                "net_tx_kbps": round(net_tx_kbps, 1),
                "disk_read_kbps": round(disk_r_kbps, 1),
                "disk_write_kbps": round(disk_w_kbps, 1),
            }
        )


if __name__ == "__main__":
    main()
