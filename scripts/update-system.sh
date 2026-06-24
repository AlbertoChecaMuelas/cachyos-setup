#!/usr/bin/env bash
set -uo pipefail
STATE_DIR="$HOME/.local/state/cachyos-setup"
LOG_FILE="$STATE_DIR/update.log"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}"
mkdir -p "$STATE_DIR"
notify() { notify-send --app-name="CachyOS Update" --urgency="$1" "$2" "$3"; }
echo "===== Actualización: $(date '+%Y-%m-%d %H:%M:%S') =====" > "$LOG_FILE"
notify normal "Actualizando sistema..." "pacman + yay en marcha"
echo "--- pacman -Syu ---" >> "$LOG_FILE"
if ! sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
    notify critical "Error al actualizar (pacman)" "Revisa $LOG_FILE"; exit 1
fi
echo "--- yay -Syu ---" >> "$LOG_FILE"
if ! yay -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
    notify critical "Error al actualizar (yay/AUR)" "Revisa $LOG_FILE"; exit 1
fi
reboot_needed=0
if grep -qiE 'upgraded (linux|nvidia)' "$LOG_FILE"; then reboot_needed=1; fi
count=$(grep -ciE '^upgraded ' "$LOG_FILE" || true)
if [[ "$reboot_needed" -eq 1 ]]; then
    notify critical "Sistema actualizado — REINICIO necesario" "Se actualizó kernel o nvidia ($count paquetes). Reinicia cuando puedas."
else
    notify normal "Sistema actualizado" "$count paquetes actualizados. No hace falta reiniciar."
fi
echo "===== Fin: $(date '+%Y-%m-%d %H:%M:%S') (reboot_needed=$reboot_needed) =====" >> "$LOG_FILE"
