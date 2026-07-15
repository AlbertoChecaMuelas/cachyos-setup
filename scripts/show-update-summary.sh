#!/usr/bin/env bash
# Muestra al usuario, al iniciar sesion grafica, el resumen persistente
# dejado por la ultima ejecucion de update-system.sh (cuando esta se
# realizo sin bus de sesion y notify-send no pudo entregar la
# notificacion). Despues de mostrarlo, borra el fichero para no
# repetirlo en logins futuros.
#
# Importante: SOLO borramos last-summary.txt (aviso efimero de login).
# El registro durable (last-run.env + last-run-packages.txt) NO se
# toca: lo consume show-last-run.sh y el modulo waybar para conocer
# el resultado de la ultima corrida en cualquier momento.
set -uo pipefail
STATE_DIR="${CACHYOS_SETUP_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
SUMMARY_FILE="$STATE_DIR/last-summary.txt"
[[ -f "$SUMMARY_FILE" ]] || exit 0
urgency=$(grep -q '^REINICIO necesario$' "$SUMMARY_FILE" && echo critical || echo normal)
title=$(sed -n '1p' "$SUMMARY_FILE")
body=$(tail -n +2 "$SUMMARY_FILE")
body="${body}"$'\n\nEjecuta show-last-run.sh para ver el detalle del último cambio.'
notify-send --app-name="CachyOS Update" --urgency="$urgency" "$title" "$body" 2>/dev/null || true
rm -f -- "$SUMMARY_FILE"
