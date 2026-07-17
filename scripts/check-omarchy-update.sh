#!/usr/bin/env bash
set -uo pipefail
OMARCHY_DIR="${OMARCHY_DIR:-$HOME/repos/forks/omarchy-on-cachyos}"
OMARCHY_URL="${OMARCHY_URL:-https://github.com/AlbertoChecaMuelas/omarchy-on-cachyos.git}"
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
# Gating de reinstalacion: versiones base (omarchy basecamp) y decision.
# Se inicializan a "" / "false" para que las ramas de early-exit
# siempre emitan las 8 claves del contrato con valores conservadores.
base_supported=""
base_available=""
base_installed=""
reinstall_allowed="false"

# Recorta espacios y elimina un prefijo "v" opcional de una version
# normalizada (p.ej. "  v3.8.3\n" -> "3.8.3").
normalize_version() {
    local v="$1"
    v="${v//[[:space:]]/}"
    v="${v#v}"
    printf '%s' "$v"
}

write_omarchy_state() {
    # Escritura atomica: tmp en el mismo dir + mv -f. Replica el
    # patron de write_last_run_record en scripts/update-system.sh.
    # El fichero final esta SIEMPRE bien formado: las 8 claves del
    # contrato se emiten aunque sean valores por defecto de borde.
    local tmp="$OMARCHY_STATE_DIR/.omarchy-check.env.tmp.$$"
    {
        echo "OMARCHY_CHECK_TIMESTAMP=\"$(date -Iseconds)\""
        echo "OMARCHY_LOCAL_VERSION=\"$local_version\""
        echo "OMARCHY_REMOTE_VERSION=\"$remote_version\""
        echo "OMARCHY_UPDATE_AVAILABLE=\"$update_available\""
        echo "OMARCHY_BASE_SUPPORTED=\"$base_supported\""
        echo "OMARCHY_BASE_AVAILABLE=\"$base_available\""
        echo "OMARCHY_BASE_INSTALLED=\"$base_installed\""
        echo "OMARCHY_REINSTALL_ALLOWED=\"$reinstall_allowed\""
    } > "$tmp"
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$ENV_FILE"
}

echo "" >> "$LOG_FILE"
echo "===== Check omarchy: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG_FILE"

# Rama de borde: OMARCHY_DIR inexistente o no es un repo git.
if [[ ! -d "$OMARCHY_DIR/.git" ]]; then
    echo "No existe $OMARCHY_DIR" >> "$LOG_FILE"
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
    write_omarchy_state
    exit 0
fi

# Determinar si hay actualizacion pendiente. Tratamos el caso de
# local sin tag como pendiente (es coherente con el script original
# y refleja que el repo local no esta al dia). Un downgrade (local
# mas nuevo que remoto) NO dispara aviso. El early-exit previo por
# `remote_version` vacio garantiza que aqui siempre es no vacio.
if [[ "$local_version" != "$remote_version" ]]; then
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

# ---- Gating de reinstalacion: versiones base + decision ----
# Solo se calculan aqui (en la ruta "feliz" tras validar local y
# remote). Las ramas de early-exit dejan base_supported/available/
# installed en "" y reinstall_allowed en "false", de modo que el
# consumidor siempre encuentra las 8 claves con valores
# conservadores.

# Version base SOPORTADA por el fork: fichero de texto plano en la
# raiz del clon local. Lectura exclusiva con head -n1; NUNCA se hace
# source del fichero para evitar ejecucion colateral.
if [[ -f "$OMARCHY_DIR/SUPPORTED_OMARCHY_VERSION" ]]; then
    base_supported=$(head -n1 "$OMARCHY_DIR/SUPPORTED_OMARCHY_VERSION" 2>/dev/null || true)
    base_supported=$(normalize_version "$base_supported")
fi

# Version base DISPONIBLE: ultimo tag de basecamp/omarchy.
# Si falla (sin red, sin tags, etc.) base_available queda vacia.
base_available=$(git ls-remote --tags --refs "https://github.com/basecamp/omarchy" 2>/dev/null \
    | sed 's@.*/@@' \
    | grep -v '\^{}' \
    | sort -V \
    | tail -n1 \
    || true)
base_available=$(normalize_version "$base_available")

# Version base INSTALADA (solo contexto): la persistimos para
# informar al visor pero NO participa en la decision del gate.
if [[ -f "$HOME/.local/share/omarchy/version" ]]; then
    base_installed=$(head -n1 "$HOME/.local/share/omarchy/version" 2>/dev/null || true)
    base_installed=$(normalize_version "$base_installed")
fi

# Gate ACTIVO solo si fork declara una version Y coincide con la
# disponible. Cualquier dato incompleto deja reinstall_allowed=false
# (degradacion segura: el visor deshabilita la accion con un mensaje
# explicativo).
if [[ -n "$base_supported" && -n "$base_available" \
      && "$base_supported" == "$base_available" ]]; then
    reinstall_allowed="true"
fi

write_omarchy_state
exit 0
