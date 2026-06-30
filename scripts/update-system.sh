#!/usr/bin/env bash
set -uo pipefail
# STATE_DIR por defecto en ~/.local/state del usuario que ejecuta; el
# unit system-level sobreescribe CACHYOS_SETUP_STATE_DIR=/var/lib/cachyos-setup.
STATE_DIR="${CACHYOS_SETUP_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
LOG_FILE="$STATE_DIR/update.log"
# Log efimero de la ejecucion actual; se trunca en cada corrida. Se
# mantiene $LOG_FILE con >> (acumulativo historico) para diagnostico.
CURRENT_RUN_LOG="$STATE_DIR/current-run.log"
SUMMARY_FILE="$STATE_DIR/last-summary.txt"
# Repo local donde aur sync deposita los paquetes AUR para que el
# pacman -Syu posterior los instale. Debe coincidir con el path
# configurado por install.sh.
AUR_REPO_DIR="/var/lib/aur-repo"
mkdir -p "$STATE_DIR"
: > "$CURRENT_RUN_LOG"

# Quien ejecuta realmente el script (root o user). Si es root bajamos
# al usuario objetivo para aur + notificaciones (aur rehúsa root y
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

write_summary() {
    # Persistir SIEMPRE el resumen de la corrida, con independencia de
    # si notify-send logro entregar la notificacion. La primera linea
    # es el titulo, el resto el body. Una linea literal
    # 'REINICIO necesario' en el titulo marca urgency=critical para el
    # script de autostart.
    local title="$1"
    local body="$2"
    {
        printf '%s\n' "$title"
        printf '%s\n' "$body"
    } > "$SUMMARY_FILE"
    # El servicio system-level corre como root; el usuario que inicia
    # sesion grafica (no root) debe poder leer este fichero para que
    # show-update-summary.sh (autostart) lo muestre y borre. Forzar
    # 644 explicitamente.
    chmod 644 "$SUMMARY_FILE" 2>/dev/null || true
}

echo "" >> "$LOG_FILE"
echo "===== Actualización: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG_FILE"
notify normal "Actualizando sistema..." "pacman oficial + AUR (aurutils)"

# ---- AUR: aur sync ANTES de pacman -Syu ----
# Compila paquetes AUR y los deposita en /var/lib/aur-repo/, que esta
# registrado como repo [aur-local] en /etc/pacman.conf (setup por
# install.sh). Asi, pacman -Syu resuelve e instala los AUR junto a
# los oficiales en un solo paso. La salida se redirige a
# $CURRENT_RUN_LOG para el parseo.
aur_failed=0
aur_pkgs=""
if [[ -n "${CACHYOS_USER:-}" && -z "${SUDO_USER:-}" ]] && [[ -z "$RUN_AS" ]]; then
    echo "(AUR omitido: falta contexto de usuario)" >> "$LOG_FILE"
    aur_failed=1
elif command -v aur >/dev/null 2>&1; then
    echo "--- aur sync -u ---" >> "$LOG_FILE"
    # --noinstall: solo construir, NO instalar. La instalacion la hace
    # el pacman -Syu posterior desde el repo local. Asi evitamos que
    # aurutils invoque sudo internamente (falla sin TTY).
    # --localrepo: aurutils usa por defecto ~/.cache/aursync; lo
    # forzamos a /var/lib/aur-repo (registrado en pacman.conf) para
    # que pacman -Syu resuelva desde ahi.
    if run_as timeout 1800 aur sync -u --noconfirm --no-view --noinstall --localrepo "$AUR_REPO_DIR" \
            > >(tee -a "$LOG_FILE" >> "$CURRENT_RUN_LOG") 2>&1; then
        # aur sync imprime ':: Sincronizando paquetes AUR...' seguido de
        # ':: Starting build de <pkg>...'. Extraemos los nombres de
        # paquetes construidos en esta corrida.
        aur_pkgs=$(grep -oE '^:: Starting build de [a-zA-Z0-9._+-]+' "$CURRENT_RUN_LOG" \
            | sed 's/^:: Starting build de //' | sort -u || true)
    else
        echo "(aur sync fallo, ver log)" >> "$LOG_FILE"
        aur_failed=1
    fi
else
    echo "(aurutils no instalado; AUR no actualizado)" >> "$LOG_FILE"
    aur_failed=1
fi

echo "--- pacman -Syu ---" >> "$LOG_FILE"
# pacman corre como root directamente (system service ya es root, o sudo
# desde terminal eleva a root). No usa sudo dentro del script. El log
# de esta corrida va a $CURRENT_RUN_LOG ademas del acumulado.
if ! pacman -Syu --noconfirm > >(tee -a "$LOG_FILE" >> "$CURRENT_RUN_LOG") 2>&1; then
    notify critical "Error al actualizar (pacman)" "Revisa $LOG_FILE"
    write_summary "Error al actualizar (pacman)" "Revisa $LOG_FILE"
    exit 1
fi

# ---- Parseo: SOLO sobre la corrida actual, NO sobre el log historico ----
reboot_needed=0
if grep -qiE 'upgrading (linux|nvidia)|upgraded (linux|nvidia)' "$CURRENT_RUN_LOG"; then reboot_needed=1; fi
pkgs=$(grep -oE '\([0-9]+/[0-9]+\) (upgrading|upgraded) [a-zA-Z0-9._+-]+' "$CURRENT_RUN_LOG" | grep -oE '[a-zA-Z0-9._+-]+$' | sort -u)
total=$(printf '%s\n' "$pkgs" | grep -c . || true)
relevant=$(printf '%s\n' "$pkgs" | grep -iE '^(linux|nvidia|systemd|glibc|openssl|mesa|xorg-server|wayland)' || true)
rel_count=$(printf '%s\n' "$relevant" | grep -c . || true)
rel_shown=$(printf '%s\n' "$relevant" | head -10)
aur_count=$(printf '%s\n' "$aur_pkgs" | grep -c . || true)
if [[ "$reboot_needed" -eq 1 ]]; then
    body="Se actualizo kernel o nvidia ($total paquetes). Reinicia cuando puedas."
    [[ "$rel_count" -gt 0 ]] && body+=$'\n\nRelevantes:\n'"$rel_shown"
    if [[ "$aur_count" -gt 0 ]]; then
        body+=$'\n\nAUR actualizados:'"$aur_pkgs"
    fi
    if [[ "$aur_failed" -eq 1 ]]; then
        body+=$'\n\n⚠ AUR no actualizado (ver log).'
    fi
    notify critical "Sistema actualizado — REINICIO necesario" "$body"
    write_summary "REINICIO necesario" "$body"
elif [[ "$total" -gt 0 ]] || [[ "$aur_count" -gt 0 ]]; then
    body="$total paquetes oficiales actualizados."
    if [[ "$aur_count" -gt 0 ]]; then
        body+=$'\nAUR actualizados:'"$aur_pkgs"
    fi
    if [[ "$rel_count" -gt 0 ]]; then
        body+=$'\n\nRelevantes:\n'"$rel_shown"
    fi
    non_rel=$(( total - rel_count ))
    if [[ "$non_rel" -gt 0 ]]; then
        body+=$'\n… y '"$non_rel"' paquetes no relevantes'
    fi
    if [[ "$aur_failed" -eq 1 ]]; then
        body+=$'\n\n⚠ AUR no actualizado (ver log).'
    fi
    notify normal "Sistema actualizado" "$body"
    write_summary "Sistema actualizado" "$body"
elif [[ "$aur_failed" -eq 1 ]]; then
    body="AUR no actualizado (ver $LOG_FILE)."
    notify normal "AUR pendiente" "$body"
    write_summary "AUR pendiente" "$body"
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
