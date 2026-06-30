#!/usr/bin/env bash
# Muestra al usuario, al iniciar sesion grafica, el resumen persistente
# dejado por la ultima ejecucion de update-system.sh (cuando esta se
# realizo sin bus de sesion y notify-send no pudo entregar la
# notificacion). Despues de mostrarlo, borra el fichero para no
# repetirlo en logins futuros.
set -uo pipefail
STATE_DIR="${CACHYOS_SETUP_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
SUMMARY_FILE="$STATE_DIR/last-summary.txt"
[[ -f "$SUMMARY_FILE" ]] || exit 0
urgency=$(grep -q '^REINICIO necesario$' "$SUMMARY_FILE" && echo critical || echo normal)
title=$(sed -n '1p' "$SUMMARY_FILE")
body=$(tail -n +2 "$SUMMARY_FILE")
notify-send --app-name="CachyOS Update" --urgency="$urgency" "$title" "$body" 2>/dev/null || true
rm -f "$SUMMARY_FILE"
