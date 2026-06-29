#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/install.sh
mkdir -p "$HOME/.local/state/cachyos-setup"
SUDOERS_FILE="$REPO_DIR/sudoers/cachyos-pacman"
SUDOERS_TMP=$(mktemp)
sed "s/@USER@/$USER/" "$SUDOERS_FILE" > "$SUDOERS_TMP"
sudo visudo -cf "$SUDOERS_TMP"
sudo install -o root -g root -m 0440 "$SUDOERS_TMP" /etc/sudoers.d/cachyos-pacman
rm -f "$SUDOERS_TMP"
mkdir -p "$SYSTEMD_USER_DIR"
# Note: paths containing '|' or '&' would break this sed substitution; normal clone paths don't.
for unit in "$REPO_DIR"/systemd/*.service "$REPO_DIR"/systemd/*.timer; do
    name=$(basename "$unit")
    target="$SYSTEMD_USER_DIR/$name"
    rm -f "$target"
    sed "s|@SCRIPTS_DIR@|$REPO_DIR/scripts|g" "$unit" > "$target"
done
systemctl --user daemon-reload
systemctl --user enable --now cachyos-update.timer
systemctl --user enable --now omarchy-check.timer
echo "Listo. Revisa los timers con: systemctl --user list-timers"
