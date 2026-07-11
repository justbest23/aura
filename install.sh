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

chmod +x scripts/pulse_daemon.py scripts/demo.sh

echo "Installed. Start the vitals daemon (the widget has nothing to read until this is running):"
echo "  systemctl --user enable --now aura-pulse.service"
echo "Then add 'Aura' via your panel's 'Add Widgets' dialog or the system"
echo "tray's '+' configure button."
echo "Requires: python-psutil (pacman -S python-psutil), and nvidia-smi for"
echo "GPU stats (optional - falls back to CPU/RAM/net/disk only)."
echo "If Plasma already has the widget cached, restart plasmashell:"
echo "  systemctl --user restart plasma-plasmashell"
echo "Want to see it react live? ./scripts/demo.sh walks through each signal"
echo "and generates a few seconds of real load for it."
