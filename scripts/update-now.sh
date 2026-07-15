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
  # cachyos-update.service es Type=oneshot, por lo que pkexec
  # systemctl start BLOQUEA hasta que el update termina (bien o
  # mal). Por eso:
  #   1. Lanzamos journalctl -f ANTES del start, para que capture el
  #      progreso en vivo durante el oneshot.
  #   2. Capturamos el rc del start SIN dejar que set -e aborte: el
  #      flujo debe continuar hasta leer last-run.env y mostrar el
  #      motivo del fallo (no cerrar la ventana al instante).
  #   3. Matamos el proceso de journalctl al retornar pkexec, para
  #      no dejar journalctl -f huerfano.
  journalctl -u cachyos-update.service -f --no-pager &
  JOURNAL_PID=$!
  rc=0
  pkexec systemctl start "$SERVICE" || rc=$?
  kill "$JOURNAL_PID" 2>/dev/null || true
  wait "$JOURNAL_PID" 2>/dev/null || true
  echo
  echo "== Actualización finalizada =="
  if [[ $rc -ne 0 ]]; then
    echo "AVISO: el servicio devolvio codigo de salida $rc (la ventana se mantiene abierta para que veas el motivo)."
  fi
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "Resultado: ${LAST_RUN_RESULT:-desconocido}"
    if [[ "${LAST_RUN_RESULT:-}" == "failure" || "${LAST_RUN_RESULT:-}" == "partial" ]]; then
      echo "Motivo:    ${LAST_RUN_FAIL_REASON:-sin detalle}"
    fi
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
