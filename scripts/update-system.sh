#!/usr/bin/env bash
set -uo pipefail
# STATE_DIR por defecto en ~/.local/state del usuario que ejecuta; el
# unit system-level sobreescribe CACHYOS_SETUP_STATE_DIR=/var/lib/cachyos-setup.
STATE_DIR="${CACHYOS_SETUP_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
LOG_FILE="$STATE_DIR/update.log"
mkdir -p "$STATE_DIR"

# Quien ejecuta realmente el script (root o user). Si es root bajamos
# al usuario objetivo para yay + notificaciones (yay rehúsa root y
# notify-send necesita el bus de sesion del usuario).
TARGET_USER=""
RUN_AS=""
if [[ "$(id -u)" -eq 0 ]]; then
    TARGET_USER="${SUDO_USER:-${CACHYOS_USER:-$(id -un)}}"
    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
        RUN_AS="runuser -u $TARGET_USER --"
    fi
fi
EFFECTIVE_USER="$(id -u ${TARGET_USER:-} 2>/dev/null || id -u)"

run_as() { if [[ -n "$RUN_AS" ]]; then $RUN_AS "$@"; else "$@"; fi; }
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/${EFFECTIVE_USER}/bus}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${EFFECTIVE_USER}}"
export HOME="${HOME:-/home/$(id -un $EFFECTIVE_USER 2>/dev/null || echo root)}"

notify() {
    # notify-send puede fallar por DBUS roto o socket perdido; lo
    # tratamos como best-effort, no abortamos.
    local out
    out=$(run_as notify-send --app-name="CachyOS Update" --urgency="$1" "$2" "$3" 2>&1) || true
    [[ -n "$out" ]] && echo "[notify warn] $out" >> "$LOG_FILE"
    return 0
}

echo "" >> "$LOG_FILE"
echo "===== Actualización: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG_FILE"
notify normal "Actualizando sistema..." "pacman oficial (AUR: ver aviso al final)"

echo "--- pacman -Syu ---" >> "$LOG_FILE"
# pacman corre como root directamente (system service ya es root, o sudo
# desde terminal eleva a root). No usa sudo dentro del script.
if ! pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
    notify critical "Error al actualizar (pacman)" "Revisa $LOG_FILE"
    exit 1
fi

echo "--- yay -Syu ---" >> "$LOG_FILE"
# yay invoca 'sudo' internamente para instalar paquetes AUR. En el
# contexto del timer (system service sin TTY), sudo falla siempre
# porque pam_unix.so fuerza conversation de password. yay entra en un
# loop interno reintentando y nunca devuelve error no-cero, asi que un
# simple '||' no basta para abortar/cerrar el bloque.
#
# Estrategia:
# - Si CACHYOS_USER esta seteado y SUDO_USER no: es el timer. Skip yay
#   totalmente (no aborta pero tampoco cuelga); el usuario corre
#   'sudo yay -Syu' en una terminal interactiva cuando quiera.
# - En cualquier otro caso (manual con sudo): corre yay con timeout
#   generoso para no colgar indefinidamente si algo va mal.
yay_failed=0
if [[ -n "${CACHYOS_USER:-}" && -z "${SUDO_USER:-}" ]]; then
    echo "(yay omitido en modo timer; ejecuta 'sudo yay -Syu' en terminal con TTY)" >> "$LOG_FILE"
    yay_failed=1
else
    run_as timeout 600 yay -Syu --noconfirm >> "$LOG_FILE" 2>&1 || yay_failed=1
fi

reboot_needed=0
if grep -qiE 'upgrading (linux|nvidia)|upgraded (linux|nvidia)' "$LOG_FILE"; then reboot_needed=1; fi
pkgs=$(grep -oE '\([0-9]+/[0-9]+\) (upgrading|upgraded) [a-zA-Z0-9._+-]+' "$LOG_FILE" | grep -oE '[a-zA-Z0-9._+-]+$' | sort -u)
total=$(printf '%s\n' "$pkgs" | grep -c . || true)
relevant=$(printf '%s\n' "$pkgs" | grep -iE '^(linux|nvidia|systemd|glibc|openssl|mesa|xorg-server|wayland)' || true)
rel_count=$(printf '%s\n' "$relevant" | grep -c . || true)
rel_shown=$(printf '%s\n' "$relevant" | head -10)
rel_shown_n=$(printf '%s\n' "$rel_shown" | grep -c . || true)
rest=$(( total - rel_shown_n ))
if [[ "$reboot_needed" -eq 1 ]]; then
    body="Se actualizo kernel o nvidia ($total paquetes). Reinicia cuando puedas."
    [[ "$rel_count" -gt 0 ]] && body+=$'\n\nRelevantes:\n'"$rel_shown"
    if [[ "$yay_failed" -eq 1 ]]; then
        body+=$'\n\n⚠ AUR no actualizado por timer. Ejecuta '\''sudo yay -Syu'\'' en tu terminal cuando quieras.'
    fi
    notify critical "Sistema actualizado — REINICIO necesario" "$body"
elif [[ "$total" -gt 0 ]]; then
    body="$total paquetes actualizados. No hace falta reiniciar."
    if [[ "$rel_count" -gt 0 ]]; then
        body+=$'\n\nRelevantes:\n'"$rel_shown"
        (( rest > 0 )) && body+=$'\n… y '"$rest"' mas'
    fi
    if [[ "$yay_failed" -eq 1 ]]; then
        body+=$'\n\n⚠ AUR no actualizado por timer. Ejecuta '\''sudo yay -Syu'\'' en tu terminal cuando quieras.'
    fi
    notify normal "Sistema actualizado" "$body"
elif [[ "$yay_failed" -eq 1 ]]; then
    # Sin updates oficiales pero yay falló: notificar AUR pendiente
    notify normal "AUR pendiente" "Ejecuta 'yay -Syu' en terminal con TTY para actualizar paquetes AUR."
fi

if [[ "$total" -gt 0 ]] && command -v needrestart >/dev/null 2>&1; then
    echo "--- needrestart ---" >> "$LOG_FILE"
    # needrestart necesita root pero su output va a un socket que
    # escribimos con >> que ya tiene los permisos OK.
    nr_out=$(/usr/bin/needrestart -b -l 2>>"$LOG_FILE" || true)
    echo "$nr_out" >> "$LOG_FILE"
    svcs=$(printf '%s\n' "$nr_out" | grep '^NEEDRESTART-SVC:' | sed 's/^NEEDRESTART-SVC:[[:space:]]*//' || true)
    if [[ -n "$svcs" ]]; then
        notify normal "Servicios pendientes de reiniciar" "$svcs"
    fi
fi

echo "===== Fin: $(date '+%Y-%m-%d %H:%M:%S') (reboot_needed=$reboot_needed) =====" >> "$LOG_FILE"
