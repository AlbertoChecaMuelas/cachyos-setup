#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
SCRIPTS_DIR="$REPO_DIR/scripts"
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/install.sh

# ---- State dir para ejecucion manual (user-level) ----
mkdir -p "$HOME/.local/state/cachyos-setup"

# ---- State dir para ejecucion automatica (system-level) ----
sudo mkdir -p /var/lib/cachyos-setup
sudo chmod 755 /var/lib/cachyos-setup

# ---- Migracion desde versiones previas (user-level cachyos-update) ----
if [ -f "$HOME/.config/systemd/user/cachyos-update.timer" ]; then
    systemctl --user disable --now cachyos-update.timer 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/cachyos-update.service" \
          "$HOME/.config/systemd/user/cachyos-update.timer"
    systemctl --user daemon-reload
fi

# ---- user-level units (omarchy-check) ----
mkdir -p "$SYSTEMD_USER_DIR"
for unit in "$REPO_DIR"/systemd/user/*.service "$REPO_DIR"/systemd/user/*.timer; do
    [ -e "$unit" ] || continue
    name=$(basename "$unit")
    target="$SYSTEMD_USER_DIR/$name"
    rm -f "$target"
    sed "s|@SCRIPTS_DIR@|$SCRIPTS_DIR|g" "$unit" > "$target"
done
systemctl --user daemon-reload
systemctl --user enable --now omarchy-check.timer

# ---- system-level units (cachyos-update, run as root) ----
USER_UID="$(id -u "$USER")"
for unit in "$REPO_DIR"/systemd/system/*.service "$REPO_DIR"/systemd/system/*.timer; do
    [ -e "$unit" ] || continue
    name=$(basename "$unit")
    target="$SYSTEMD_SYSTEM_DIR/$name"
    sudo sed -e "s|@SCRIPTS_DIR@|$SCRIPTS_DIR|g" \
              -e "s|@USER@|$USER|g" \
              -e "s|@UID@|$USER_UID|g" "$unit" | sudo tee "$target" > /dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable --now cachyos-update.timer

echo "Listo. Timers:"
echo "  systemctl --user list-timers      (omarchy-check)"
echo "  systemctl list-timers --all       (cachyos-update)"
if ! command -v needrestart >/dev/null 2>&1; then
    cat <<'EOF'

AVISO: needrestart no esta instalado.
  Para detectar servicios pendientes de reiniciar tras actualizar
  (recomendado): yay -S needrestart
  Sin el, update-system.sh funciona identico, simplemente no avisa de
  procesos con .so antiguas en memoria.
EOF
fi
