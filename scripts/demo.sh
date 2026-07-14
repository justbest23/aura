#!/bin/bash
# Walks through Aura's six signals, generating a few seconds of real load
# for each. Pass stage names to run just those (e.g. `./demo.sh ram` or
# `./demo.sh net disk`); no args runs all six. Every stage self-terminates
# via `timeout` and the EXIT trap cleans up, so Ctrl-C is safe at any point.
set -uo pipefail

STAGES=(cpu ram gpu net disk proc)

usage() {
    echo "usage: $0 [stage ...]"
    echo "stages: ${STAGES[*]} (default: all, in that order)"
    echo "aliases: memory, network, io, processes, swarm"
    exit "${1:-1}"
}

SCRATCH_FILES=()
BG_PIDS=()

cleanup() {
    for pid in "${BG_PIDS[@]:-}"; do
        # INT not TERM - ffmpeg sprays demux errors on SIGTERM
        kill -INT "$pid" 2>/dev/null
    done
    for f in "${SCRATCH_FILES[@]:-}"; do
        [[ -n "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT
# Without the exit, Ctrl-C only kills the current stage and the demo carries on
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

# --- CPU: core color + pulse speed -----------------------------------------
stage_cpu() {
    say "CPU — watch the core: it should shift from cool blue toward red, and its breathing should speed up as the clock boosts toward turbo."
    local workers=$(( $(nproc) / 2 ))
    for ((i = 0; i < workers; i++)); do
        timeout 8 yes > /dev/null &
        BG_PIDS+=($!)
    done
    countdown 9
    say "CPU stress done — core should be cooling back to blue and slowing down."
    sleep 2
}

# --- RAM: the swirl inside the core ------------------------------------------
stage_ram() {
    say "RAM — watch the swirl INSIDE the core: the churning rods should multiply into a dense cloud as memory fills toward 80%, thinning back out when it's released."
    # Top up to 80% of total RAM, chunked so the swirl visibly climbs, but keep
    # a floor of available memory so a busy machine can't get pushed into swap.
    # bytearray() memsets, so the pages are really committed.
    timeout -s INT 35 python3 - <<'PYEOF' &
import time
mem = {}
with open("/proc/meminfo") as f:
    for line in f:
        key, val = line.split(":")
        mem[key] = int(val.split()[0]) * 1024
total, avail = mem["MemTotal"], mem["MemAvailable"]
floor = max(total // 10, 1 << 30)  # keep >=10% (min 1 GiB) available
need = min(int(total * 0.8) - (total - avail), avail - floor)
bufs, chunk = [], 256 << 20
while need > 0:
    bufs.append(bytearray(min(chunk, need)))
    need -= chunk
time.sleep(6)
PYEOF
    BG_PIDS+=($!)
    countdown 20
    say "Memory released — the core's swirl should be thinning back out."
    sleep 2
}

# --- GPU: the aura bloom -----------------------------------------------------
stage_gpu() {
    local ffmpeg_filters
    ffmpeg_filters=$(command -v ffmpeg >/dev/null && ffmpeg -hide_banner -filters 2>/dev/null)
    if ! grep -q scale_cuda <<< "$ffmpeg_filters"; then
        say "GPU — skipped (no ffmpeg build with scale_cuda found; needs an NVIDIA GPU + ffmpeg built with CUDA filters)."
        return
    fi
    # Keep the load entirely on the GPU or this stage lights up the CPU core
    # too: encode a tiny clip once, then loop NVDEC decode + CUDA scaling so
    # the CPU only demuxes a small file from page cache.
    local clip clip_encoder=libx264
    clip=$(mktemp "$HOME/.cache/aura-demo-XXXXXX.mp4")
    SCRATCH_FILES+=("$clip")
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_nvenc && clip_encoder=h264_nvenc
    ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 2 -c:v "$clip_encoder" -pix_fmt yuv420p "$clip"
    say "GPU — watch for a second-colored bloom swelling out AROUND the core (independent of the core's own color/pulse). Driving 4 parallel NVDEC + CUDA-scaling pipelines, all in GPU memory."
    for ((i = 0; i < 4; i++)); do
        timeout -s INT 8 ffmpeg -hide_banner -nostdin -loglevel error -hwaccel cuda -hwaccel_output_format cuda \
            -stream_loop -1 -i "$clip" \
            -vf "scale_cuda=3840:2160,scale_cuda=1280:720,scale_cuda=3840:2160" \
            -f null - &
        BG_PIDS+=($!)
    done
    countdown 9
    say "GPU stress done — aura should be shrinking back down."
    rm -f "$clip"
    sleep 2
}

# --- Network: the cyan ring ---------------------------------------------------
stage_net() {
    # Must be real traffic on a real interface - the daemon ignores loopback.
    # Downloading from a speed-test server also calibrates the ring's ceiling.
    # (OVH's proof server; Cloudflare 403s plain curl.)
    if ! command -v curl >/dev/null || ! curl -sf --max-time 3 -o /dev/null "https://proof.ovh.net/files/1Mb.dat"; then
        say "Network — skipped (needs curl and an internet connection; loopback traffic doesn't count as network)."
        return
    fi
    say "Network — watch the cyan ring: it should spin up and brighten. Downloading from a speed-test server for 6s (3 parallel streams)."
    for ((i = 0; i < 3; i++)); do
        curl -s --max-time 6 -o /dev/null "https://proof.ovh.net/files/10Gb.dat" &
        BG_PIDS+=($!)
    done
    countdown 7
    say "Network burst done — cyan ring should be settling back down."
    sleep 2
}

# --- Disk: the amber ring ------------------------------------------------------
stage_disk() {
    say "Disk — watch the amber ring: it spins the OPPOSITE way from the cyan one. Hammering a scratch file with direct writes for 5s."
    # Not /tmp - it's often tmpfs, and RAM-backed writes never hit the disk counters
    local scratch
    scratch=$(mktemp "$HOME/.cache/aura-demo-XXXXXX.bin")
    SCRATCH_FILES+=("$scratch")
    timeout 5 bash -c "while true; do dd if=/dev/zero of='$scratch' bs=1M count=200 oflag=direct status=none; done"
    rm -f "$scratch"
    say "Disk stress done — amber ring should be settling back down."
    sleep 2
}

# --- Processes: the firefly swarm ----------------------------------------------
stage_proc() {
    say "Processes — watch the drifting swarm of specks around the orb: it should multiply severalfold and brighten. Spawning ~400 short-lived processes for 6s."
    for ((i = 0; i < 400; i++)); do
        sleep 6 &
        BG_PIDS+=($!)
    done
    countdown 7
    say "Swarm should be thinning back out."
    sleep 2
}

# Accept a few obvious aliases per stage
normalize() {
    case "$1" in
        cpu) echo cpu ;;
        ram|mem|memory) echo ram ;;
        gpu) echo gpu ;;
        net|network) echo net ;;
        disk|io) echo disk ;;
        proc|procs|process|processes|swarm) echo proc ;;
        *) return 1 ;;
    esac
}

selected=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage 0 ;;
    esac
    stage=$(normalize "${arg,,}") || { echo "unknown stage: $arg"; usage; }
    selected+=("$stage")
done
[[ ${#selected[@]} -eq 0 ]] && selected=("${STAGES[@]}")

echo "Aura demo - open the widget (panel/tray) now if it isn't already."
echo "Running ${#selected[@]} stage(s): ${selected[*]}"
echo "Ctrl-C at any point stops the demo immediately and cleans up."
countdown 3

for stage in "${selected[@]}"; do
    "stage_$stage"
done

echo
echo "Demo done."
