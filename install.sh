#!/bin/bash
# install.sh - symlinks the plasmoid and the systemd unit into place so
# edits in this repo take effect without reinstalling.
set -euo pipefail
cd "$(dirname "$0")"
REPO=$(pwd)

mkdir -p ~/.local/share/plasma/plasmoids ~/.config/systemd/user ~/.cache/aura
rm -rf ~/.local/share/plasma/plasmoids/org.aura.systempulse
ln -sf "$REPO/plasmoid" ~/.local/share/plasma/plasmoids/org.aura.systempulse

ln -sf "$REPO/systemd/aura-pulse.service" ~/.config/systemd/user/aura-pulse.service
systemctl --user daemon-reload

chmod +x plasmoid/contents/scripts/pulse_daemon.py scripts/demo.sh

echo "Installed. Add 'Aura' via your panel's 'Add Widgets' dialog or the"
echo "system tray's '+' configure button - the widget starts its own sampler."
echo "Optional: run the sampler as a service instead (survives reboots"
echo "without the widget having to kick it):"
echo "  systemctl --user enable --now aura-pulse.service"
echo "nvidia-smi enables GPU stats (optional - falls back to CPU/RAM/net/disk)."
echo "If Plasma already has the widget cached, restart plasmashell:"
echo "  systemctl --user restart plasma-plasmashell"
echo "Want to see it react live? ./scripts/demo.sh walks through each signal"
echo "and generates a few seconds of real load for it."
