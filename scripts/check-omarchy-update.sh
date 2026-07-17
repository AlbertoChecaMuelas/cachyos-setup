#!/usr/bin/env bash
set -uo pipefail
OMARCHY_DIR="${OMARCHY_DIR:-$HOME/repos/forks/omarchy-on-cachyos}"
OMARCHY_URL="${OMARCHY_URL:-https://github.com/mroboff/omarchy-on-cachyos.git}"
OMARCHY_STATE_DIR="${OMARCHY_STATE_DIR:-$HOME/.local/state/cachyos-setup}"
LOG_FILE="$OMARCHY_STATE_DIR/omarchy-check.log"
ENV_FILE="$OMARCHY_STATE_DIR/omarchy-check.env"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}"
mkdir -p "$OMARCHY_STATE_DIR"
notify() { notify-send --app-name="Omarchy" --urgency="$1" "$2" "$3" || true; }

# Resultado del check; se persiste en el env durable al final.
local_version=""
remote_version=""
update_available="false"
check_reason=""

write_omarchy_state() {
    # Escritura atomica: tmp en el mismo dir + mv -f. Replica el
    # patron de write_last_run_record en scripts/update-system.sh.
    # El fichero final esta SIEMPRE bien formado: las 4 claves del
    # contrato se emiten aunque sean valores por defecto de borde.
    local tmp="$OMARCHY_STATE_DIR/.omarchy-check.env.tmp.$$"
    {
        echo "OMARCHY_CHECK_TIMESTAMP=\"$(date -Iseconds)\""
        echo "OMARCHY_LOCAL_VERSION=\"$local_version\""
        echo "OMARCHY_REMOTE_VERSION=\"$remote_version\""
        echo "OMARCHY_UPDATE_AVAILABLE=\"$update_available\""
    } > "$tmp"
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$ENV_FILE"
}

echo "" >> "$LOG_FILE"
echo "===== Check omarchy: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG_FILE"

# Rama de borde: OMARCHY_DIR inexistente o no es un repo git.
if [[ ! -d "$OMARCHY_DIR/.git" ]]; then
    echo "No existe $OMARCHY_DIR" >> "$LOG_FILE"
    check_reason="OMARCHY_DIR inexistente"
    write_omarchy_state
    exit 0
fi

local_version=$(git -C "$OMARCHY_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")
echo "Versión local: $local_version" >> "$LOG_FILE"

remote_version=$(git ls-remote --tags --refs "$OMARCHY_URL" 2>>"$LOG_FILE" | sed 's@.*/@@' | sort -V | tail -n1 || true)
echo "Versión upstream: $remote_version" >> "$LOG_FILE"

# Rama de borde: upstream ilegible.
if [[ -z "$remote_version" ]]; then
    echo "No se pudo leer upstream" >> "$LOG_FILE"
    check_reason="upstream ilegible"
    write_omarchy_state
    exit 0
fi

# Determinar si hay actualizacion pendiente. Tratamos el caso de
# local sin tag como pendiente (es coherente con el script original
# y refleja que el repo local no esta al dia). Un downgrade (local
# mas nuevo que remoto) NO dispara aviso.
if [[ -n "$remote_version" && "$local_version" != "$remote_version" ]]; then
    if [[ -z "$local_version" ]]; then
        update_available="true"
    else
        mayor=$(printf '%s\n%s\n' "$local_version" "$remote_version" | sort -V | tail -n1)
        if [[ "$mayor" == "$remote_version" ]]; then
            update_available="true"
        fi
    fi
    if [[ "$update_available" == "true" ]]; then
        notify normal "Nueva versión de omarchy disponible: $remote_version" "Tienes $local_version. Revisa el upstream para actualizar (no se instala solo)."
        echo "AVISO: nueva versión $remote_version" >> "$LOG_FILE"
    fi
fi

if [[ -n "$local_version" && "$local_version" == "$remote_version" ]]; then
    echo "OK: al día (versión $remote_version)" >> "$LOG_FILE"
fi

write_omarchy_state
exit 0
