#!/bin/bash
# demo.sh - walks through Aura's five signals one at a time, printing what to
# look for right before generating a few seconds of real load for that
# signal. Open the Aura widget first, then run this alongside it.
#
# Every stage is self-terminating (via `timeout`) and the EXIT trap sweeps up
# anything left running or on disk, so Ctrl-C at any point is safe.
set -uo pipefail

SCRATCH_FILE=""
BG_PIDS=()

cleanup() {
    for pid in "${BG_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null
    done
    [[ -n "$SCRATCH_FILE" && -f "$SCRATCH_FILE" ]] && rm -f "$SCRATCH_FILE"
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
echo "Five stages, ~10s each: CPU, GPU, network, disk, process count."
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

# --- GPU: the aura bloom -----------------------------------------------------
ffmpeg_filters=$(command -v ffmpeg >/dev/null && ffmpeg -hide_banner -filters 2>/dev/null)
if grep -q scale_cuda <<< "$ffmpeg_filters"; then
    say "GPU — watch for a second-colored bloom swelling out AROUND the core (independent of the core's own color/pulse). Driving 4 parallel GPU upscale pipelines, no files written."
    for ((i = 0; i < 4; i++)); do
        timeout 8 ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=3840x2160:rate=60 \
            -vf "hwupload_cuda,scale_cuda=3840:2160" -f null - &
        BG_PIDS+=($!)
    done
    countdown 9
    say "GPU stress done — aura should be shrinking back down."
    sleep 2
else
    say "GPU — skipped (no ffmpeg build with scale_cuda found; needs an NVIDIA GPU + ffmpeg built with CUDA filters)."
fi

# --- Network: the cyan ring ---------------------------------------------------
if command -v socat >/dev/null; then
    say "Network — watch the cyan ring: it should spin up and brighten. Blasting loopback traffic for 6s (nothing leaves the machine)."
    port=$(( (RANDOM % 20000) + 20000 ))
    timeout 6 socat -u TCP-LISTEN:"$port",reuseaddr,fork /dev/null &
    BG_PIDS+=($!)
    sleep 0.3
    timeout 5 socat -u /dev/zero TCP:localhost:"$port" &
    BG_PIDS+=($!)
    countdown 7
    say "Network burst done — cyan ring should be settling back down."
    sleep 2
else
    say "Network — skipped (socat not found)."
fi

# --- Disk: the amber ring ------------------------------------------------------
say "Disk — watch the amber ring: it spins the OPPOSITE way from the cyan one. Hammering a scratch file with direct writes for 5s."
# Not /tmp: on many distros (including this one) it's tmpfs (RAM-backed),
# so writes there never touch a real block device and psutil's disk
# counters - and the amber ring - never see them.
SCRATCH_FILE=$(mktemp "$HOME/.cache/aura-demo-XXXXXX.bin")
timeout 5 bash -c "while true; do dd if=/dev/zero of='$SCRATCH_FILE' bs=1M count=200 oflag=direct status=none; done"
rm -f "$SCRATCH_FILE"
SCRATCH_FILE=""
say "Disk stress done — amber ring should be settling back down."
sleep 2

# --- Processes: the firefly swarm ----------------------------------------------
say "Processes — watch the drifting swarm of specks around the orb: it should get noticeably thicker. Spawning ~400 short-lived processes for 6s."
for ((i = 0; i < 400; i++)); do
    sleep 6 &
    BG_PIDS+=($!)
done
countdown 7
say "Swarm should be thinning back out."

echo
echo "Demo done. That's all five signals: CPU core (color + pulse), GPU aura,"
echo "network ring (cyan), disk ring (amber), and the process swarm."
