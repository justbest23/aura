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
CALIBRATION_FILE = os.path.join(STATE_DIR, "calibration.json")

# Ring "100%" reference for network/disk throughput, per machine. Starts at a
# generic guess and ratchets up (never down) the first time real traffic
# beats it - e.g. running scripts/demo.sh's network/disk stages teaches it
# this machine's real ceiling in one pass. Persisted so it survives restarts.
#
# Capped per metric: net_io_counters() includes loopback, and demo.sh's
# network stage deliberately uses loopback (self-contained, no real transfer)
# to get a big burst safely - which hits RAM speed (tens of Gbps), not real
# network speed. Uncapped, that one demo run would permanently peg the ring's
# "100%" so high that even a maxed-out real gigabit link looked idle. The
# caps are generous (10Gbps / 8GB/s) - well above realistic home/office
# network and consumer NVMe throughput - so genuine fast hardware still
# calibrates correctly; only the synthetic loopback figure gets clamped.
DEFAULT_MAX_KBPS = 100000.0  # 100 MB/s
NET_MAX_CAP_KBPS = 1250000.0  # 10 Gbps
DISK_MAX_CAP_KBPS = 8000000.0  # 8 GB/s
CALIBRATION_CAPS = {
    "net_max_kbps": NET_MAX_CAP_KBPS,
    "net_rx_max_kbps": NET_MAX_CAP_KBPS,
    "net_tx_max_kbps": NET_MAX_CAP_KBPS,
    "disk_max_kbps": DISK_MAX_CAP_KBPS,
    "disk_read_max_kbps": DISK_MAX_CAP_KBPS,
    "disk_write_max_kbps": DISK_MAX_CAP_KBPS,
}
CALIBRATION_KEYS = tuple(CALIBRATION_CAPS.keys())


def load_calibration() -> dict:
    try:
        with open(CALIBRATION_FILE) as f:
            saved = json.load(f)
        return {key: saved.get(key, DEFAULT_MAX_KBPS) for key in CALIBRATION_KEYS}
    except Exception:
        return {key: DEFAULT_MAX_KBPS for key in CALIBRATION_KEYS}


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


def write_json(path: str, data: dict) -> None:
    tmp_path = path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, path)


def main() -> None:
    os.makedirs(STATE_DIR, exist_ok=True)

    psutil.cpu_percent(interval=None)  # first call is meaningless, per psutil docs
    prev_net = psutil.net_io_counters()
    prev_disk = psutil.disk_io_counters()
    prev_t = time.time()
    gpu_pct = gpu_temp = gpu_mem_pct = None
    calibration = load_calibration()

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

        observed = {
            "net_max_kbps": net_rx_kbps + net_tx_kbps,
            "net_rx_max_kbps": net_rx_kbps,
            "net_tx_max_kbps": net_tx_kbps,
            "disk_max_kbps": disk_r_kbps + disk_w_kbps,
            "disk_read_max_kbps": disk_r_kbps,
            "disk_write_max_kbps": disk_w_kbps,
        }
        new_maxes = {
            key: min(CALIBRATION_CAPS[key], max(calibration[key], observed[key]))
            for key in CALIBRATION_KEYS
        }
        if new_maxes != calibration:
            calibration = new_maxes
            write_json(CALIBRATION_FILE, calibration)

        write_json(
            STATE_FILE,
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
                **calibration,
            },
        )


if __name__ == "__main__":
    main()
