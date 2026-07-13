#!/bin/bash
# demo.sh - walks through Aura's six signals one at a time, printing what to
# look for right before generating a few seconds of real load for that
# signal. Open the Aura widget first, then run this alongside it.
#
# Every stage is self-terminating (via `timeout`) and the EXIT trap sweeps up
# anything left running or on disk, so Ctrl-C at any point is safe.
set -uo pipefail

SCRATCH_FILES=()
BG_PIDS=()

cleanup() {
    for pid in "${BG_PIDS[@]:-}"; do
        # INT not TERM: ffmpeg treats SIGINT as a graceful quit, SIGTERM as
        # an emergency stop that sprays demux errors; everything else here
        # (yes/socat/sleep) exits the same either way.
        kill -INT "$pid" 2>/dev/null
    done
    for f in "${SCRATCH_FILES[@]:-}"; do
        [[ -n "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT
# A trap that doesn't call exit just resumes the script afterward - without
# this, Ctrl-C only killed the current stage's load and the demo carried on
# to the next stage, so quitting took one Ctrl-C per remaining stage.
trap 'echo; echo "Stopping."; exit 130' INT TERM

say() {
    echo
    echo ">> $1"
}

countdown() {
    local secs=$1
    for ((i = secs; i > 0; i--)); do
        printf "\r   ...%ds " "$i"
        sleep 1
    done
    printf "\r          \r"
}

echo "Aura demo - open the widget (panel/tray) now if it isn't already."
echo "Six stages, ~10s each: CPU, RAM, GPU, network, disk, process count."
echo "Ctrl-C at any point stops the demo immediately and cleans up."
countdown 3

# --- CPU: core color + pulse speed -----------------------------------------
say "CPU — watch the core: it should shift from cool blue toward red, and its breathing should speed up as the clock boosts toward turbo."
workers=$(( $(nproc) / 2 ))
for ((i = 0; i < workers; i++)); do
    timeout 8 yes > /dev/null &
    BG_PIDS+=($!)
done
countdown 9
say "CPU stress done — core should be cooling back to blue and slowing down."
sleep 2

# --- RAM: core size -----------------------------------------------------------
say "RAM — watch the swirl INSIDE the core: the churning wisps should get denser and brighter as memory fills, thinning back out when it's released. Holding a few GB of allocated memory for 6s."
# A quarter of total RAM, but never more than half of what's actually free,
# so this can't push a busy/small machine into swap. bytearray() memsets, so
# every page is really committed - a lazily-mapped zero page would never
# show up in the RAM numbers at all.
timeout -s INT 15 python3 - <<'PYEOF' &
import time
mem = {}
with open("/proc/meminfo") as f:
    for line in f:
        key, val = line.split(":")
        mem[key] = int(val.split()[0]) * 1024
buf = bytearray(int(min(mem["MemTotal"] * 0.25, mem["MemAvailable"] * 0.5)))
time.sleep(6)
PYEOF
BG_PIDS+=($!)
countdown 9
say "Memory released — the core's swirl should be thinning back out."
sleep 2

# --- GPU: the aura bloom -----------------------------------------------------
ffmpeg_filters=$(command -v ffmpeg >/dev/null && ffmpeg -hide_banner -filters 2>/dev/null)
if grep -q scale_cuda <<< "$ffmpeg_filters"; then
    # The load has to live entirely on the GPU, or this stage lights up the
    # CPU core as much as the aura (an earlier version synthesized raw 4K
    # frames with lavfi on the CPU and merely uploaded them). So: encode a
    # tiny 2s clip once up front (NVENC when available, so even that is GPU
    # work), then loop-decode it with NVDEC and bounce every frame through a
    # chain of CUDA scale kernels - decode, filtering, and all the frame
    # buffers stay in GPU memory; the CPU only demuxes a small file from
    # page cache.
    DEMO_CLIP=$(mktemp "$HOME/.cache/aura-demo-XXXXXX.mp4")
    SCRATCH_FILES+=("$DEMO_CLIP")
    clip_encoder=libx264
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_nvenc && clip_encoder=h264_nvenc
    ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 2 -c:v "$clip_encoder" -pix_fmt yuv420p "$DEMO_CLIP"
    say "GPU — watch for a second-colored bloom swelling out AROUND the core (independent of the core's own color/pulse). Driving 4 parallel NVDEC + CUDA-scaling pipelines, all in GPU memory."
    # -s INT: SIGINT is ffmpeg's graceful "q" - plain SIGTERM mid-loop makes
    # it spray demux errors all over the terminal on the way out.
    for ((i = 0; i < 4; i++)); do
        timeout -s INT 8 ffmpeg -hide_banner -nostdin -loglevel error -hwaccel cuda -hwaccel_output_format cuda \
            -stream_loop -1 -i "$DEMO_CLIP" \
            -vf "scale_cuda=3840:2160,scale_cuda=1280:720,scale_cuda=3840:2160" \
            -f null - &
        BG_PIDS+=($!)
    done
    countdown 9
    say "GPU stress done — aura should be shrinking back down."
    rm -f "$DEMO_CLIP"
    sleep 2
else
    say "GPU — skipped (no ffmpeg build with scale_cuda found; needs an NVIDIA GPU + ffmpeg built with CUDA filters)."
fi

# --- Network: the cyan ring ---------------------------------------------------
# Real traffic on a real interface: the daemon excludes loopback from its
# network counters (localhost transfers run at RAM speed and aren't network),
# so the old socat-to-localhost trick no longer registers at all. A few
# parallel downloads from a speed-test file server also teach the calibration
# this machine's actual download ceiling, which is exactly what the ring's
# "100%" is supposed to mean. (OVH's proof server, not Cloudflare's endpoint
# - Cloudflare 403s plain curl.)
if command -v curl >/dev/null && curl -sf --max-time 3 -o /dev/null "https://proof.ovh.net/files/1Mb.dat"; then
    say "Network — watch the cyan ring: it should spin up and brighten. Downloading from a speed-test server for 6s (3 parallel streams)."
    for ((i = 0; i < 3; i++)); do
        curl -s --max-time 6 -o /dev/null "https://proof.ovh.net/files/10Gb.dat" &
        BG_PIDS+=($!)
    done
    countdown 7
    say "Network burst done — cyan ring should be settling back down."
    sleep 2
else
    say "Network — skipped (needs curl and an internet connection; loopback traffic doesn't count as network)."
fi

# --- Disk: the amber ring ------------------------------------------------------
say "Disk — watch the amber ring: it spins the OPPOSITE way from the cyan one. Hammering a scratch file with direct writes for 5s."
# Not /tmp: on many distros (including this one) it's tmpfs (RAM-backed),
# so writes there never touch a real block device and psutil's disk
# counters - and the amber ring - never see them.
DISK_SCRATCH=$(mktemp "$HOME/.cache/aura-demo-XXXXXX.bin")
SCRATCH_FILES+=("$DISK_SCRATCH")
timeout 5 bash -c "while true; do dd if=/dev/zero of='$DISK_SCRATCH' bs=1M count=200 oflag=direct status=none; done"
rm -f "$DISK_SCRATCH"
say "Disk stress done — amber ring should be settling back down."
sleep 2

# --- Processes: the firefly swarm ----------------------------------------------
say "Processes — watch the drifting swarm of specks around the orb: it should multiply severalfold and brighten. Spawning ~400 short-lived processes for 6s."
for ((i = 0; i < 400; i++)); do
    sleep 6 &
    BG_PIDS+=($!)
done
countdown 7
say "Swarm should be thinning back out."

echo
echo "Demo done. That's all six signals: CPU core (color + pulse), the core's"
echo "swirl density (RAM), GPU aura, network ring (cyan), disk ring (amber),"
echo "and the process swarm."
