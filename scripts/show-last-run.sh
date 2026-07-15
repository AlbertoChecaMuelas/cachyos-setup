#!/usr/bin/env bash
# Visor legible del registro durable dejado por update-system.sh.
# Pensado para abrirse en una terminal flotante desde el modulo
# waybar (click izquierdo). Si no existe todavia ningun run, lo dice
# y sale sin error.
#
# Patron de terminal: omarchy-launch-floating-terminal-with-presentation
# si esta disponible (mismo patron que el resto de scripts del repo);
# en caso contrario degrada a ${TERMINAL:-alacritty}.
set -euo pipefail

STATE_DIR="${STATE_DIR:-${CACHYOS_SETUP_STATE_DIR:-/var/lib/cachyos-setup}}"
ENV_FILE="$STATE_DIR/last-run.env"
PKG_FILE="$STATE_DIR/last-run-packages.txt"

render() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "No hay ningún registro de actualización todavía."
    return 0
  fi
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  echo "== Última actualización del sistema =="
  echo "Fecha:     ${LAST_RUN_TIMESTAMP:-desconocida}"
  # Tres valores posibles para LAST_RUN_RESULT:
  #   success  -> pacman Y AUR OK
  #   partial  -> pacman OK pero AUR fallo (estado diferenciado)
  #   failure  -> pacman fallo (sin distinguir AUR)
  case "${LAST_RUN_RESULT:-}" in
    success)
      echo "Resultado: success"
      ;;
    partial)
      echo "Resultado: partial (Actualización parcial: pacman OK, AUR falló)"
      echo "Motivo:    ${LAST_RUN_FAIL_REASON:-sin detalle}"
      ;;
    failure)
      echo "Resultado: failure"
      echo "Motivo:    ${LAST_RUN_FAIL_REASON:-sin detalle}"
      ;;
    *)
      echo "Resultado: ${LAST_RUN_RESULT:-desconocido}"
      ;;
  esac
  echo "Paquetes:  ${LAST_RUN_PACKAGE_COUNT:-0}"
  if [[ "${LAST_RUN_REBOOT_NEEDED:-false}" == "true" ]]; then
    echo "Reinicio:  RECOMENDADO (kernel/nvidia actualizados)"
  else
    echo "Reinicio:  no necesario"
  fi
  if [[ -s "$PKG_FILE" ]]; then
    echo
    echo "-- Paquetes actualizados --"
    cat "$PKG_FILE"
  fi
}

if [[ "${CACHYOS_INLINE:-0}" == "1" ]]; then
  render
  echo
  read -rp "Pulsa Enter para cerrar..." _
  exit 0
fi

if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
  exec omarchy-launch-floating-terminal-with-presentation "CACHYOS_INLINE=1 $0"
else
  TERM_EMU="${TERMINAL:-alacritty}"
  exec "$TERM_EMU" -e bash -lc "CACHYOS_INLINE=1 '$0'"
fi
