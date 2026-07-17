#!/usr/bin/env bash
# Visor legible del registro durable dejado por update-system.sh y
# del estado durable de omarchy dejado por check-omarchy-update.sh.
# Pensado para abrirse en una terminal flotante desde el modulo
# waybar (click izquierdo). Si no existe todavia ningun run, lo dice
# y sale sin error.
#
# El visor ofrece ademas una accion interactiva para forzar la
# comprobacion de omarchy bajo demanda (ejecuta
# check-omarchy-update.sh en el MISMO proceso, sin pkexec: el
# servicio omarchy-check es user-level y solo hace lectura de red),
# re-renderizando el bloque de omarchy en vivo dentro de la misma
# ventana. La instalacion de la nueva version de omarchy es MANUAL
# y nunca se hace sola.
#
# Patron de terminal: omarchy-launch-floating-terminal-with-presentation
# si esta disponible (mismo patron que el resto de scripts del repo);
# en caso contrario degrada a ${TERMINAL:-alacritty}.
set -euo pipefail

STATE_DIR="${STATE_DIR:-${CACHYOS_SETUP_STATE_DIR:-/var/lib/cachyos-setup}}"
ENV_FILE="$STATE_DIR/last-run.env"
PKG_FILE="$STATE_DIR/last-run-packages.txt"
# Estado de omarchy vive en el state dir USER-level (no root), no en
# $STATE_DIR. El modulo waybar lanza el visor sin override de env, asi
# que el default debe apuntar a la ruta real del usuario.
OMARCHY_STATE_DIR="${OMARCHY_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
OMARCHY_ENV_FILE="$OMARCHY_STATE_DIR/omarchy-check.env"
# Localizacion del script de comprobacion junto al visor (mismo dir).
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_OMARCHY_SCRIPT="$SCRIPTS_DIR/check-omarchy-update.sh"

render() {
  echo "== Última actualización del sistema =="
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "No hay ningún registro de actualización todavía."
  else
    # shellcheck source=/dev/null
    source "$ENV_FILE"
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
  fi

  echo
  echo "== Comprobación de omarchy-on-cachyos =="
  if [[ ! -f "$OMARCHY_ENV_FILE" ]]; then
    echo "Estado:    aún no comprobado (el script check-omarchy-update.sh aún no ha escrito su estado)."
    echo "Local:     —"
    echo "Remota:    —"
    echo "Pendiente: —"
  else
    # shellcheck source=/dev/null
    (
        source "$OMARCHY_ENV_FILE"
        echo "Fecha:     ${OMARCHY_CHECK_TIMESTAMP:-desconocida}"
        echo "Local:     ${OMARCHY_LOCAL_VERSION:-desconocida}"
        echo "Remota:    ${OMARCHY_REMOTE_VERSION:-desconocida}"
        if [[ "${OMARCHY_UPDATE_AVAILABLE:-false}" == "true" ]]; then
            echo "Pendiente: SÍ (actualización disponible)"
        else
            echo "Pendiente: no"
        fi
    )
  fi
  echo
  echo "Nota: la instalación de una nueva versión de omarchy es MANUAL y"
  echo "      queda fuera de este repo. Aquí solo se informa del estado."
}

if [[ "${CACHYOS_INLINE:-0}" == "1" ]]; then
  # Bucle interactivo: cada iteracion muestra el render y propone
  # acciones. "c" re-comprueba omarchy y re-renderiza. Enter cierra.
  # Cerramos la ventana al recibir Enter, pero NO al comprobar.
  while true; do
    render
    echo
    printf '%s' "[c] Comprobar omarchy ahora   [Enter] Cerrar > "
    if ! read -r action; then
      # EOF (p.ej. stdin cerrado en un test): salimos sin error.
      exit 0
    fi
    case "${action:-}" in
      c|C|r|R)
        echo
        echo "Comprobando omarchy..."
        if [[ -x "$CHECK_OMARCHY_SCRIPT" ]]; then
          "$CHECK_OMARCHY_SCRIPT" || true
        else
          bash "$CHECK_OMARCHY_SCRIPT" || true
        fi
        echo
        ;;
      "")
        exit 0
        ;;
      *)
        echo "Tecla no reconocida."
        ;;
    esac
  done
fi

if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
  exec omarchy-launch-floating-terminal-with-presentation "CACHYOS_INLINE=1 $0"
else
  TERM_EMU="${TERMINAL:-alacritty}"
  exec "$TERM_EMU" -e bash -lc "CACHYOS_INLINE=1 '$0'"
fi
