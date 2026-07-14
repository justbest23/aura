# Aura

An ambient system-vitals widget for KDE Plasma 6. Abstract at a glance — a
breathing orb, a colored aura, a drifting swarm, two spinning rings — but
every layer is driven by a real number, and the popup (or tray tooltip)
shows the exact figures.

## What drives the visual

- **Core** (brightest, center) — **CPU + RAM**. Color shifts blue → red with
  CPU heat (utilization or package temp). Breathing speed tracks clock boost,
  which is deliberately separate from the color — a single latency-bound core
  can boost to max while utilization stays low. Inside the core, **RAM is the
  density of a churning swirl of tiny rods**: a few drifting specks when
  memory is free, a dense cloud when it's nearly full.
- **Aura** (bloom around the core) — **GPU**, with its own color from GPU
  heat. Nearly invisible at idle, blooms under load.
- **Swarm** (drifting motes) — **process count relative to this machine's
  normal**. The daemon learns a slow baseline and the swarm reacts to the
  surge above it, since the absolute count barely moves on a desktop.
- **Cyan ring** — **network** throughput. **Amber ring** — **disk**,
  spinning the opposite way. Fixed colors so they stay recognizable. Each
  can optionally split into two counter-rotating rings (down/up, read/write).
  At zero activity they creep (~60s/turn) instead of stopping dead.

  Ring speed/brightness scales against a per-machine "100%": a moving max
  that jumps on new peaks and decays with a ~12h half-life (persisted in
  `~/.cache/aura/calibration.json`). Loopback is excluded from the network
  counters. Response is square-root rather than linear so everyday traffic
  doesn't disappear at the bottom of the scale.

## Components

### `plasmoid/`

Plasma 6 applet (`org.aura.systempulse`). Polls `~/.cache/aura/stats.json`
every 200ms and renders the orb in both the tray icon and the popup; the
popup also lists exact readings, EMA-smoothed to stop flicker. Settings
(right-click → Configure Aura…): fade duration, breathing pulse on/off,
sensor readings as numbers and/or ~60s sparklines, panel background on/off,
and split network/disk rings.

### `plasmoid/contents/scripts/pulse_daemon.py`

Sampler daemon, pure Python stdlib (reads `/proc` and `/sys` directly, so
there's nothing to install). Writes `stats.json` ~5x/sec: CPU%/temp/clock,
RAM, net/disk throughput, process count + baseline, and GPU stats via
`nvidia-smi` (~1x/sec, skipped without an NVIDIA GPU). The widget spawns it
automatically when stats are missing or stale — an flock keeps it to one
instance — so the systemd unit is optional. It ships inside the plasmoid
package, so a store install is self-contained.

### `scripts/demo.sh`

Walks through the six signals, printing what to look for and then generating
a few seconds of that load. The RAM stage fills memory to ~80% of total
(always leaving a safety floor so it can't push a busy machine into swap).
Every stage is `timeout`-bound and an EXIT trap cleans up, so Ctrl-C is safe
at any point.

```
./scripts/demo.sh              # all six stages
./scripts/demo.sh ram          # just one
./scripts/demo.sh net disk     # any subset, in the order given
```

Stages: `cpu ram gpu net disk proc` (aliases like `memory`, `network`,
`processes` work too).

The GPU stage needs an NVIDIA GPU and an ffmpeg build with CUDA filters; the
network stage needs curl and internet (it downloads from a speed-test
server, which also calibrates the ring's ceiling). Both are skipped with a
message if unavailable.

## Requirements

- KDE Plasma 6 (python3 comes with it)
- `nvidia-smi` for GPU stats (optional)

## Install

```
./install.sh
```

Symlinks the plasmoid and systemd unit into place, so repo edits take effect
without reinstalling (plasmashell needs a restart to pick up QML changes).
Then add "Aura" from your panel's "Add Widgets" dialog or the system tray's
configure button — the widget starts its own sampler. Optionally run the
sampler as a service instead:

```
systemctl --user enable --now aura-pulse.service
```
