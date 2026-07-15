#!/usr/bin/env bash
# Disparo manual de la actualizacion: escala privilegios con pkexec
# (regla polkit 49-cachyos-update.rules) para arrancar
# cachyos-update.service y observa el progreso. NO reimplementa la
# logica de actualizacion: update-system.sh es la unica fuente.
# Al terminar, lee el registro durable y recomienda reinicio si
# corresponde (unica via posible: LAST_RUN_REBOOT_NEEDED).
set -euo pipefail

STATE_DIR="${STATE_DIR:-${CACHYOS_SETUP_STATE_DIR:-/var/lib/cachyos-setup}}"
ENV_FILE="$STATE_DIR/last-run.env"
SERVICE="cachyos-update.service"

run_update() {
  echo "== Disparando actualización manual =="
  pkexec systemctl start "$SERVICE"
  echo "Servicio iniciado. Siguiendo el progreso..."
  journalctl -u "$SERVICE" -f --no-pager &
  JPID=$!
  while systemctl is-active --quiet "$SERVICE"; do sleep 2; done
  kill "$JPID" 2>/dev/null || true
  echo
  echo "== Actualización finalizada =="
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "Resultado: ${LAST_RUN_RESULT:-desconocido}"
    if [[ "${LAST_RUN_REBOOT_NEEDED:-false}" == "true" ]]; then
      echo ">>> Se RECOMIENDA reiniciar el sistema (kernel/nvidia actualizados)."
    fi
  fi
  read -rp "Pulsa Enter para cerrar..." _
}

if [[ "${CACHYOS_INLINE:-0}" == "1" ]]; then
  run_update
  exit 0
fi

if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
  exec omarchy-launch-floating-terminal-with-presentation "CACHYOS_INLINE=1 $0"
else
  TERM_EMU="${TERMINAL:-alacritty}"
  exec "$TERM_EMU" -e bash -lc "CACHYOS_INLINE=1 '$0'"
fi
