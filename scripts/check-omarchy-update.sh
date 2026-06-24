#!/usr/bin/env bash
set -uo pipefail
OMARCHY_DIR="$HOME/repos/forks/omarchy-on-cachyos"
UPSTREAM_URL="https://github.com/mroboff/omarchy-on-cachyos.git"
STATE_DIR="$HOME/.local/state/cachyos-setup"
LOG_FILE="$STATE_DIR/omarchy-check.log"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}"
mkdir -p "$STATE_DIR"
notify() { notify-send --app-name="Omarchy" --urgency="$1" "$2" "$3"; }
echo "===== Check omarchy: $(date '+%Y-%m-%d %H:%M:%S') =====" > "$LOG_FILE"
if [[ ! -d "$OMARCHY_DIR/.git" ]]; then echo "No existe $OMARCHY_DIR" >> "$LOG_FILE"; exit 0; fi
current=$(git -C "$OMARCHY_DIR" describe --tags --abbrev=0 2>/dev/null)
echo "Versión local: $current" >> "$LOG_FILE"
latest=$(git ls-remote --tags --refs "$UPSTREAM_URL" 2>>"$LOG_FILE" | sed 's@.*/@@' | sort -V | tail -n1)
echo "Versión upstream: $latest" >> "$LOG_FILE"
if [[ -z "$latest" ]]; then echo "No se pudo leer upstream" >> "$LOG_FILE"; exit 0; fi
if [[ "$current" != "$latest" ]]; then
    mayor=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)
    if [[ "$mayor" == "$latest" ]]; then
        notify normal "Nueva versión de omarchy disponible: $latest" "Tienes $current. Revisa el upstream para actualizar (no se instala solo)."
        echo "AVISO: nueva versión $latest" >> "$LOG_FILE"
    fi
fi
