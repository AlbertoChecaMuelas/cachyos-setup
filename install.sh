#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SYSTEMD="$HOME/.config/systemd/user"
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/install.sh
mkdir -p "$HOME/.local/state/cachyos-setup"
sudo visudo -cf "$REPO_DIR/sudoers/cachyos-pacman"
sudo install -o root -g root -m 0440 "$REPO_DIR/sudoers/cachyos-pacman" /etc/sudoers.d/cachyos-pacman
mkdir -p "$USER_SYSTEMD"
for unit in "$REPO_DIR"/systemd/*; do ln -sf "$unit" "$USER_SYSTEMD/$(basename "$unit")"; done
systemctl --user daemon-reload
systemctl --user enable --now cachyos-update.timer
systemctl --user enable --now omarchy-check.timer
echo "Listo. Revisa los timers con: systemctl --user list-timers"
