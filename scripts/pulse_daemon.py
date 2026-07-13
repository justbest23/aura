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

# Ring "100%" reference for network/disk throughput, per machine: a MOVING
# max, not a permanent ratchet. It jumps up instantly when real traffic
# beats it (e.g. running scripts/demo.sh's network/disk stages teaches it
# this machine's real ceiling in one pass), then decays back down with a
# ~12h half-life toward the default floor - so one freak burst (a synthetic
# benchmark, a one-off cache-speed copy) stops defining "100%" within a day
# instead of permanently pinning the rings near zero for all normal traffic.
# Persisted so it survives restarts.
#
# The per-metric caps are a sanity bound well above realistic home/office
# network and consumer NVMe throughput. Loopback is excluded from the
# network counters entirely (localhost transfers run at RAM speed and
# aren't network activity in any sense the cyan ring cares about).
# Floors are per medium: 100 MB/s is a fine "minimum max" for disk (slow
# SATA territory) but absurd for network, where it would pin a modest
# broadband line's ring near zero forever.
NET_FLOOR_KBPS = 12500.0  # ~100 Mbit
DISK_FLOOR_KBPS = 100000.0  # 100 MB/s
NET_MAX_CAP_KBPS = 1250000.0  # 10 Gbps
DISK_MAX_CAP_KBPS = 8000000.0  # 8 GB/s
CALIBRATION_DECAY = 0.5 ** (INTERVAL / (12 * 3600))  # per-tick factor, 12h half-life
CALIBRATION_SAVE_EVERY = 3000  # persist decay progress every ~10min
CALIBRATION_CAPS = {
    "net_max_kbps": NET_MAX_CAP_KBPS,
    "net_rx_max_kbps": NET_MAX_CAP_KBPS,
    "net_tx_max_kbps": NET_MAX_CAP_KBPS,
    "disk_max_kbps": DISK_MAX_CAP_KBPS,
    "disk_read_max_kbps": DISK_MAX_CAP_KBPS,
    "disk_write_max_kbps": DISK_MAX_CAP_KBPS,
}
CALIBRATION_FLOORS = {
    key: NET_FLOOR_KBPS if key.startswith("net") else DISK_FLOOR_KBPS
    for key in CALIBRATION_CAPS
}
CALIBRATION_KEYS = tuple(CALIBRATION_CAPS.keys())


def load_calibration() -> dict:
    try:
        with open(CALIBRATION_FILE) as f:
            saved = json.load(f)
        return {key: saved.get(key, CALIBRATION_FLOORS[key]) for key in CALIBRATION_KEYS}
    except Exception:
        return {key: CALIBRATION_FLOORS[key] for key in CALIBRATION_KEYS}


def net_totals():
    """Total rx/tx bytes across real interfaces - loopback excluded, since
    localhost transfers run at RAM speed and aren't network activity."""
    per_nic = psutil.net_io_counters(pernic=True)
    rx = sum(c.bytes_recv for name, c in per_nic.items() if name != "lo")
    tx = sum(c.bytes_sent for name, c in per_nic.items() if name != "lo")
    return rx, tx


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
    prev_net = net_totals()
    prev_disk = psutil.disk_io_counters()
    prev_t = time.time()
    gpu_pct = gpu_temp = gpu_mem_pct = None
    calibration = load_calibration()
    proc_baseline = None

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

        net = net_totals()
        disk = psutil.disk_io_counters()
        net_rx_kbps = (net[0] - prev_net[0]) / 1024 / dt
        net_tx_kbps = (net[1] - prev_net[1]) / 1024 / dt
        disk_r_kbps = (disk.read_bytes - prev_disk.read_bytes) / 1024 / dt
        disk_w_kbps = (disk.write_bytes - prev_disk.write_bytes) / 1024 / dt
        prev_net, prev_disk = net, disk

        if tick % GPU_EVERY == 0:
            gpu_pct, gpu_temp, gpu_mem_pct = gpu_stats()

        # The absolute process count barely moves in relative terms (a desktop
        # idles at several hundred), so the widget's swarm reacts to the count
        # relative to this baseline: it chases downward quickly (~4s) but
        # upward only over minutes, so a burst of spawned processes stands
        # well above it for its whole lifetime instead of dragging the
        # reference up with it.
        proc_count = len(psutil.pids())
        if proc_baseline is None:
            proc_baseline = float(proc_count)
        elif proc_count < proc_baseline:
            proc_baseline += (proc_count - proc_baseline) * 0.05
        else:
            proc_baseline += (proc_count - proc_baseline) * 0.002

        observed = {
            "net_max_kbps": net_rx_kbps + net_tx_kbps,
            "net_rx_max_kbps": net_rx_kbps,
            "net_tx_max_kbps": net_tx_kbps,
            "disk_max_kbps": disk_r_kbps + disk_w_kbps,
            "disk_read_max_kbps": disk_r_kbps,
            "disk_write_max_kbps": disk_w_kbps,
        }
        # Moving max: jump up instantly on a new peak, decay slowly otherwise,
        # never below the default floor or above the sanity cap.
        new_maxes = {
            key: min(
                CALIBRATION_CAPS[key],
                max(CALIBRATION_FLOORS[key], calibration[key] * CALIBRATION_DECAY, observed[key]),
            )
            for key in CALIBRATION_KEYS
        }
        # Decay changes every tick; only persist new peaks immediately and
        # checkpoint the decay every ~10min instead of rewriting 5x/sec.
        ratcheted = any(new_maxes[key] > calibration[key] for key in CALIBRATION_KEYS)
        calibration = new_maxes
        if ratcheted or tick % CALIBRATION_SAVE_EVERY == 0:
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
                "proc_count": proc_count,
                "proc_baseline": round(proc_baseline),
                "net_rx_kbps": round(net_rx_kbps, 1),
                "net_tx_kbps": round(net_tx_kbps, 1),
                "disk_read_kbps": round(disk_r_kbps, 1),
                "disk_write_kbps": round(disk_w_kbps, 1),
                **calibration,
            },
        )


if __name__ == "__main__":
    main()
