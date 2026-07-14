#!/usr/bin/env python3
"""Vitals sampler. Writes ~/.cache/aura/stats.json every ~200ms; the widget
just cats it. The widget spawns this itself when stats go stale (the flock
makes duplicate spawns exit), or it can run via systemd/aura-pulse.service.
Pure stdlib on purpose - a store-installed widget can't pull in psutil."""
import fcntl
import glob
import json
import os
import re
import subprocess
import sys
import time

INTERVAL = 0.2
GPU_EVERY = 5  # nvidia-smi every ~1s
STATE_DIR = os.path.expanduser("~/.cache/aura")
STATE_FILE = os.path.join(STATE_DIR, "stats.json")
CALIBRATION_FILE = os.path.join(STATE_DIR, "calibration.json")
LOCK_FILE = os.path.join(STATE_DIR, "daemon.lock")

# Per-machine "100%" for the rings: a moving max that jumps on new peaks and
# decays back toward the floor with a ~12h half-life, so one freak burst
# doesn't pin the rings near zero forever. Persisted across restarts.
NET_FLOOR_KBPS = 12500.0  # ~100 Mbit
DISK_FLOOR_KBPS = 100000.0  # 100 MB/s
NET_MAX_CAP_KBPS = 1250000.0  # 10 Gbps
DISK_MAX_CAP_KBPS = 8000000.0  # 8 GB/s
CALIBRATION_DECAY = 0.5 ** (INTERVAL / (12 * 3600))
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

# Whole disks only - counting partitions would double every byte
DISK_DEV_RE = re.compile(r"^(sd[a-z]+|vd[a-z]+|nvme\d+n\d+|mmcblk\d+)$")


def acquire_lock():
    os.makedirs(STATE_DIR, exist_ok=True)
    lock = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # another instance is running
    lock.write(str(os.getpid()))
    lock.flush()
    return lock  # keep the fd (and the lock) alive for the process lifetime


def load_calibration() -> dict:
    try:
        with open(CALIBRATION_FILE) as f:
            saved = json.load(f)
        return {key: saved.get(key, CALIBRATION_FLOORS[key]) for key in CALIBRATION_KEYS}
    except Exception:
        return {key: CALIBRATION_FLOORS[key] for key in CALIBRATION_KEYS}


def cpu_times():
    with open("/proc/stat") as f:
        vals = [int(x) for x in f.readline().split()[1:]]
    return sum(vals), vals[3] + vals[4]  # total, idle+iowait


def cpu_freq_mhz():
    cur, mins, maxes = [], [], []
    for policy in glob.glob("/sys/devices/system/cpu/cpufreq/policy*"):
        try:
            with open(os.path.join(policy, "scaling_cur_freq")) as f:
                cur.append(int(f.read()))
            with open(os.path.join(policy, "cpuinfo_min_freq")) as f:
                mins.append(int(f.read()))
            with open(os.path.join(policy, "cpuinfo_max_freq")) as f:
                maxes.append(int(f.read()))
        except OSError:
            continue
    if not cur:
        return None, None, None
    return sum(cur) / len(cur) / 1000, min(mins) / 1000, max(maxes) / 1000


def find_cpu_temp_file():
    for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(os.path.join(hwmon, "name")) as f:
                name = f.read().strip()
        except OSError:
            continue
        if name not in ("coretemp", "k10temp"):
            continue
        fallback = None
        for label_path in sorted(glob.glob(os.path.join(hwmon, "temp*_label"))):
            input_path = label_path.replace("_label", "_input")
            with open(label_path) as f:
                if f.read().strip() in ("Package id 0", "Tctl"):
                    return input_path
            fallback = fallback or input_path
        inputs = sorted(glob.glob(os.path.join(hwmon, "temp*_input")))
        return fallback or (inputs[0] if inputs else None)
    return None


def read_temp(path):
    if path is None:
        return None
    try:
        with open(path) as f:
            return int(f.read()) / 1000
    except OSError:
        return None


def meminfo():
    mem = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, val = line.split(":")
            mem[key] = int(val.split()[0]) * 1024
    return mem["MemTotal"], mem["MemAvailable"]


def net_totals():
    """rx/tx bytes across real interfaces; loopback isn't network activity."""
    rx = tx = 0
    with open("/proc/net/dev") as f:
        for line in f.readlines()[2:]:
            name, rest = line.split(":", 1)
            if name.strip() == "lo":
                continue
            fields = rest.split()
            rx += int(fields[0])
            tx += int(fields[8])
    return rx, tx


def disk_totals():
    """read/written bytes across whole disks (/proc/diskstats sectors are 512B)."""
    read = written = 0
    with open("/proc/diskstats") as f:
        for line in f:
            fields = line.split()
            if DISK_DEV_RE.match(fields[2]):
                read += int(fields[5]) * 512
                written += int(fields[9]) * 512
    return read, written


def proc_count():
    return sum(1 for d in os.listdir("/proc") if d.isdigit())


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


def write_json(path: str, data: dict) -> None:
    tmp_path = path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, path)


def main() -> None:
    lock = acquire_lock()  # noqa: F841 - dropping the ref would close the fd and release the lock

    temp_file = find_cpu_temp_file()
    prev_cpu = cpu_times()
    prev_net = net_totals()
    prev_disk = disk_totals()
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

        cpu = cpu_times()
        d_total, d_idle = cpu[0] - prev_cpu[0], cpu[1] - prev_cpu[1]
        cpu_pct = (1 - d_idle / d_total) * 100 if d_total > 0 else 0.0
        prev_cpu = cpu

        freq_cur, freq_min, freq_max = cpu_freq_mhz()
        mem_total, mem_avail = meminfo()

        net = net_totals()
        disk = disk_totals()
        net_rx_kbps = (net[0] - prev_net[0]) / 1024 / dt
        net_tx_kbps = (net[1] - prev_net[1]) / 1024 / dt
        disk_r_kbps = (disk[0] - prev_disk[0]) / 1024 / dt
        disk_w_kbps = (disk[1] - prev_disk[1]) / 1024 / dt
        prev_net, prev_disk = net, disk

        if tick % GPU_EVERY == 0:
            gpu_pct, gpu_temp, gpu_mem_pct = gpu_stats()

        # Baseline chases the count down quickly but up only over minutes,
        # so a burst of spawned processes stands above it for its lifetime.
        procs = proc_count()
        if proc_baseline is None:
            proc_baseline = float(procs)
        elif procs < proc_baseline:
            proc_baseline += (procs - proc_baseline) * 0.05
        else:
            proc_baseline += (procs - proc_baseline) * 0.002

        observed = {
            "net_max_kbps": net_rx_kbps + net_tx_kbps,
            "net_rx_max_kbps": net_rx_kbps,
            "net_tx_max_kbps": net_tx_kbps,
            "disk_max_kbps": disk_r_kbps + disk_w_kbps,
            "disk_read_max_kbps": disk_r_kbps,
            "disk_write_max_kbps": disk_w_kbps,
        }
        new_maxes = {
            key: min(
                CALIBRATION_CAPS[key],
                max(CALIBRATION_FLOORS[key], calibration[key] * CALIBRATION_DECAY, observed[key]),
            )
            for key in CALIBRATION_KEYS
        }
        # Persist peaks immediately, checkpoint decay every ~10min.
        ratcheted = any(new_maxes[key] > calibration[key] for key in CALIBRATION_KEYS)
        calibration = new_maxes
        if ratcheted or tick % CALIBRATION_SAVE_EVERY == 0:
            write_json(CALIBRATION_FILE, calibration)

        write_json(
            STATE_FILE,
            {
                "ts": round(now, 1),
                "cpu_pct": round(cpu_pct, 1),
                "cpu_temp": read_temp(temp_file),
                "cpu_freq_cur": round(freq_cur, 0) if freq_cur else None,
                "cpu_freq_min": round(freq_min, 0) if freq_min else None,
                "cpu_freq_max": round(freq_max, 0) if freq_max else None,
                "ram_pct": round((1 - mem_avail / mem_total) * 100, 1),
                "ram_used_gb": round((mem_total - mem_avail) / 1024**3, 1),
                "ram_total_gb": round(mem_total / 1024**3, 1),
                "gpu_pct": gpu_pct,
                "gpu_temp": gpu_temp,
                "gpu_mem_pct": gpu_mem_pct,
                "proc_count": procs,
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
