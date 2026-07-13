# Aura

An ambient system-vitals widget for KDE Plasma 6. Abstract at a glance — a
breathing orb, a colored aura, a drifting swarm, two spinning rings — but
every layer is driven by a real number underneath, and opening the popup (or
hovering the tray icon) shows the exact figures.

## What drives the visual

- **Core** (brightest, center) — **CPU + RAM**. Color shifts blue → red with
  CPU heat (utilization, package temp). Breathing speed tracks how hard the
  clock is currently boosting (idle park speed → turbo), which is
  deliberately a *different* signal from the color: a single latency-bound
  core can boost to max while overall utilization/color stays calm. Inside
  the core, **RAM usage is the density of a churning swirl** — a machine
  with free memory shows a dim shell with a few embers drifting around in
  it; as memory fills, the wisps multiply and brighten until the core
  churns nearly solid. Independent of what the color and pulse are doing.
- **Aura** (soft bloom around the core) — **GPU**. Its own independent color
  from GPU heat (utilization, memory, temp). Nearly invisible at idle,
  visibly blooms out under load (gaming, rendering, GPU compute).
- **Swarm** (drifting motes) — **process count relative to this machine's
  normal**. The absolute count is a poor signal (a desktop idles at several
  hundred processes and rarely moves by more than a few percent), so the
  daemon learns a baseline — chasing drops quickly, rises only over minutes —
  and the swarm reacts to the *surge* above it: a handful of ambient motes at
  rest, multiplying and brightening when something spawns a burst of
  processes (a build, a demo stage), then thinning back out.
- **Cyan ring** — **network** throughput (rx+tx). **Amber ring** — **disk**
  throughput (read+write), spinning the opposite direction. Both are fixed
  colors regardless of load, so they stay recognizable no matter what the
  core/aura are doing. Each can optionally split into two counter-rotating
  rings (download/upload, read/write) instead of one combined ring. At zero
  activity a ring doesn't stop dead - it creeps around very slowly (~60s per
  turn) rather than looking broken.

  Ring speed/brightness is scaled against a per-machine "100%" reference: a
  **moving max** that jumps up instantly when real traffic beats it and then
  decays with a ~12h half-life, so a ring at max spin means max for *this*
  machine's actual hardware — and one freak burst (a synthetic benchmark, a
  one-off cache-speed copy) stops defining "100%" within a day instead of
  permanently pinning the rings near zero. Loopback is excluded from the
  network counters entirely (localhost transfers run at RAM speed and
  aren't network activity), and generous sanity caps (10Gbps / 8GB/s) bound
  the reference — see `scripts/pulse_daemon.py`. The rings' response to
  rate/max is square-root rather than linear: everyday traffic is a few
  percent of a fast machine's ceiling, which linearly would be an invisible
  ring; sqrt keeps the top anchored but makes "some traffic" visibly
  different from "none".

## Components

### `plasmoid/`

A native Plasma 6 system-tray applet (`org.aura.systempulse`). Every 200ms it
`cat`s `~/.cache/aura/stats.json` via the `executable` data engine and
renders `PulseOrb.qml` in both the compact (tray icon) and full (popup)
representations — the popup also lists CPU/RAM/GPU/network/disk/process
readings, each smoothed with an exponential moving average (raw 200ms
samples are individually noisy - without smoothing, both the text and the
orb's own color/pulse flicker). Settings live at right-click → Configure
Aura…:

- **Fade duration** — how long a signal takes to visibly ease toward a new
  reading instead of snapping (default 1500ms).
- **Enable breathing pulse** — the core/aura's size-pulsing can be turned
  off entirely. The rings and swarm don't depend on it at all, so they stay
  fully animated either way; this only holds the core/aura at a steady size.
- **Show exact sensor readings** — toggles the per-metric rows under the
  orb entirely, for when you just want the orb itself.
- **Show as** — per-metric rows can show the number, a ~60s sparkline, or
  both. Each chart is color-matched to its ring/aura (cyan network, amber
  disk, etc.) and auto-scaled to its own recent range.
- **Show panel background** — toggles the popup's background/border
  (`Plasmoid.backgroundHints`); off gives a borderless, transparent orb, e.g.
  for dropping onto the desktop rather than the tray.
- **Show network upload/download separately** / **Show disk read/write
  separately** — split the combined ring into two counter-rotating rings
  per direction (download vs. upload, read vs. write).

### `scripts/pulse_daemon.py`

A small long-running sampler (uses `psutil`) that writes
`~/.cache/aura/stats.json` roughly 5x/second — CPU%/temp/clock, RAM, network
and disk throughput (delta since last tick), process count (plus the learned
baseline the swarm measures surges against), and GPU
utilization/temp/memory via `nvidia-smi` (refreshed ~1x/second since spawning
`nvidia-smi` is comparatively slow; skipped gracefully if there's no NVIDIA
GPU). Also maintains `~/.cache/aura/calibration.json`, the per-machine "100%"
throughput reference described above. Runs as `systemd/aura-pulse.service`.
The widget just reads the file the daemon keeps warm, rather than forking
`python3` + importing `psutil` on every poll — the cheap way to get a
sub-second refresh rate.

### `scripts/demo.sh`

Walks through the six signals one at a time: prints what to look for, then
generates a few real seconds of that specific load (CPU, RAM, GPU, network,
disk, process count) so you can watch the widget react live. The RAM stage
holds a real allocation for a few seconds (a quarter of total RAM, capped at
half of what's currently free so it can't push a busy machine into swap).
Every stage
self-terminates (`timeout`-bound) and an `EXIT` trap sweeps up anything left
running or on disk; Ctrl-C at any point stops the whole demo immediately,
not just the current stage. The disk stage writes its scratch file under
`~/.cache`, not `/tmp` — on many distros (including a default CachyOS
install) `/tmp` is tmpfs (RAM-backed), so writes there never touch a real
block device and the amber ring (and disk calibration) would never see them.
Run it alongside the widget:

```
./scripts/demo.sh
```

The GPU stage needs an NVIDIA GPU + an `ffmpeg` build with CUDA filters
(`scale_cuda`); the network stage needs `curl` and an internet connection
(it downloads from Cloudflare's speed-test endpoint — loopback traffic is
excluded from the network counters, so a localhost blast wouldn't register).
Both are auto-detected and skipped with a message if unavailable — the
other four stages have no extra dependencies beyond coreutils and python3. The GPU stage keeps its load entirely
on the GPU (NVDEC loop-decode of a pre-encoded clip, bounced through chained
CUDA scale kernels in GPU memory) so the CPU core stays calm while the aura
blooms — synthesizing test frames on the CPU and uploading them would light
up both at once and muddy what the stage is demonstrating.

## Requirements

- KDE Plasma 6, `python-psutil`
- `nvidia-smi` for GPU stats (optional — NVIDIA only; without it the aura
  and popup just omit GPU)

## Install

```
./install.sh
```

Symlinks the plasmoid and the systemd unit into place, so edits in this repo
take effect without reinstalling (the plasmoid needs `systemctl --user
restart plasma-plasmashell` to pick up changes if it's already running; the
daemon picks up changes on its own next restart). Then:

```
systemctl --user enable --now aura-pulse.service
```

and add "Aura" from your panel's "Add Widgets" dialog or the system tray's
configure button.
