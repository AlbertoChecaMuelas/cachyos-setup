#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolver el usuario real (el que invoca sudo, o el usuario activo si
# se ejecuta sin sudo). Todo lo que toca paths de usuario debe usar
# $TARGET_HOME / $TARGET_USER; $HOME bajo sudo apunta a /root.
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
SYSTEMD_USER_DIR="$TARGET_HOME/.config/systemd/user"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
# SCRIPTS_DIR es la ruta instalada final de TODOS los scripts del repo
# (update-system.sh, show-update-summary.sh, show-last-run.sh,
# update-now.sh). Los units systemd referencian esta ruta via
# @SCRIPTS_DIR@; el modulo waybar (Phase 4) la usa como destino de
# on-click / on-click-right. Mantener sincronizada con la seccion de
# despliegue de scripts de abajo.
SCRIPTS_DIR="$REPO_DIR/scripts"
# Patron de despliegue de scripts: el repositorio ES el destino.
# Cualquier *.sh nuevo bajo scripts/ queda ejecutable de forma
# idempotente sin necesidad de una copia ni de reinstalacion manual.
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/install.sh

# Verificacion explicita de los scripts del visor y del disparo
# manual: deben existir junto a update-system.sh / show-update-summary.sh
# y ser ejecutables. Si falta alguno, abortamos: el modulo waybar y el
# polkit los referencian y un install roto dejaria el sistema sin
# camino para disparar/recomendar actualizaciones.
for required_script in update-system.sh show-update-summary.sh show-last-run.sh update-now.sh; do
    if [[ ! -x "$SCRIPTS_DIR/$required_script" ]]; then
        echo "ERROR: falta o no es ejecutable $SCRIPTS_DIR/$required_script" >&2
        exit 1
    fi
done

# ---- State dir para ejecucion manual (user-level) ----
mkdir -p "$TARGET_HOME/.local/state/cachyos-setup"

# ---- State dir para ejecucion automatica (system-level) ----
sudo mkdir -p /var/lib/cachyos-setup
sudo chmod 755 /var/lib/cachyos-setup

# ---- Regla polkit: autorizar a wheel a iniciar cachyos-update.service ----
# Permite que el disparo manual (update-now.sh) escale privilegios
# con pkexec sin reintroducir reglas sudoers de password vacio (que
# install.sh acaba de purgar lineas arriba). Polkit relee las reglas
# en cuanto aparece el fichero, no hace falta reiniciar el daemon.
POLKIT_SRC="$REPO_DIR/etc/polkit-1/rules.d/49-cachyos-update.rules"
POLKIT_DST="/etc/polkit-1/rules.d/49-cachyos-update.rules"
if [ -f "$POLKIT_SRC" ]; then
    sudo install -d -m 0755 /etc/polkit-1/rules.d
    # Idempotente: install copia el fichero y aplica 0644 root:root.
    sudo install -m 0644 "$POLKIT_SRC" "$POLKIT_DST"
    echo "Regla polkit cachyos-update instalada en $POLKIT_DST."
else
    echo "Regla polkit no presente en el repo; se omite."
fi

# ---- Migracion: purgar sudoers legacy de despliegues previos ----
# En versiones anteriores se desplegaba /etc/sudoers.d/cachyos-pacman con
# reglas NOPASSWD para sudo/pacman. El nuevo modelo corre como root
# directo desde un unit system-level, por lo que ese fichero no debe
# existir. Migracion idempotente: si esta, se elimina y se avisa.
if [ -f /etc/sudoers.d/cachyos-pacman ]; then
    sudo rm -f /etc/sudoers.d/cachyos-pacman
    echo "Migracion: eliminado /etc/sudoers.d/cachyos-pacman (legacy, ya no necesario)."
fi

# ---- AUR: aurutils + repo local para actualizacion automatica ----
# aurutils NO esta en repos oficiales, hay que bootstrappear desde AUR.
# Si ya hay un helper AUR (yay/paru) lo usamos; si no, compilamos
# aurutils con makepkg (aseguramos base-devel + git si faltan). Tras
# instalarlo, configuramos un repo local /var/lib/aur-repo/ donde
# aur sync deposita los paquetes y pacman -Syu los resuelve como
# cualquier repo.
AUR_REPO_DIR="/var/lib/aur-repo"
if ! command -v aur >/dev/null 2>&1; then
    if command -v yay >/dev/null 2>&1; then
        su - "$TARGET_USER" -c "yay -S --noconfirm --needed aurutils"
    elif command -v paru >/dev/null 2>&1; then
        su - "$TARGET_USER" -c "paru -S --noconfirm --needed aurutils"
    else
        # Sin helper AUR: bootstrap directo con makepkg.
        if ! pacman -Qg base-devel | grep -q .; then
            sudo pacman -S --needed --noconfirm base-devel
        fi
        command -v git >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm git
        su - "$TARGET_USER" <<'INNER'
set -e
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
git clone https://aur.archlinux.org/aurutils.git "$tmpdir/aurutils"
(cd "$tmpdir/aurutils" && makepkg -si --noconfirm --needed)
INNER
    fi
fi
sudo mkdir -p "$AUR_REPO_DIR"
sudo chown "$TARGET_USER":"$TARGET_USER" "$AUR_REPO_DIR"
if ! ls "$AUR_REPO_DIR"/aur-local.db.tar.gz >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" bash -c "cd '$AUR_REPO_DIR' && bsdtar -czf aur-local.db.tar.gz -T /dev/null && ln -sf aur-local.db.tar.gz aur-local.db"
fi
if ! grep -q '^\[aur-local\]' /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[aur-local]
SigLevel = Optional TrustAll
Server = file://$AUR_REPO_DIR
EOF
fi
# Importar la clave GPG de aurutils (idempotente).
sudo -u "$TARGET_USER" bash -c 'command -v aur-key >/dev/null 2>&1 && aur-key || true' || true

# ---- Migracion desde versiones previas (user-level cachyos-update) ----
# Bajo sudo, $HOME apunta a /root; debemos mirar la HOME del usuario
# real (TARGET_HOME) para encontrar el timer antiguo. Ademas, el
# disable opera sobre el bus de usuario del TARGET_USER, no del root
# que ejecuta install.sh; runuser baja al uid del usuario real para
# que systemctl --user funcione.
if [ -f "$TARGET_HOME/.config/systemd/user/cachyos-update.timer" ]; then
    runuser -u "$TARGET_USER" -- systemctl --user disable --now cachyos-update.timer 2>/dev/null || true
    rm -f "$TARGET_HOME/.config/systemd/user/cachyos-update.service" \
          "$TARGET_HOME/.config/systemd/user/cachyos-update.timer"
    runuser -u "$TARGET_USER" -- systemctl --user daemon-reload 2>/dev/null || true
fi

# ---- Autostart: mostrar resumen persistente de updates al iniciar sesion ----
# Cuando el timer corre sin sesion grafica, las notificaciones se
# persisten en $STATE_DIR/last-summary.txt. Este script de autostart lo
# muestra al iniciar sesion y luego lo borra para no repetirlo.
# El STATE_DIR debe coincidir con el del unit system-level (que fija
# CACHYOS_SETUP_STATE_DIR=/var/lib/cachyos-setup); si no, el script
# busca en ~/.local/state/... y nunca encuentra el summary.
AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/cachyos-update-summary.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CachyOS Update Summary
Exec=env CACHYOS_SETUP_STATE_DIR=/var/lib/cachyos-setup "$SCRIPTS_DIR/show-update-summary.sh"
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF
chmod 644 "$AUTOSTART_DIR/cachyos-update-summary.desktop"

# ---- Waybar: fusion idempotente del modulo de acceso CachyOS Update ----
# Si el usuario tiene ~/.config/waybar/ desplegado (omarchy o
# configuracion propia), añadimos UN unico modulo custom con dos
# acciones: ver el ultimo resultado (visor) y disparar la
# actualizacion manual (pkexec). La fusion es NO destructiva:
#   1. Backup timestamp SOLO la primera vez (un *.cachyos.bak-*).
#   2. Bloque delimitado por marcadores (idempotente: re-ejecutar
#      sustituye el bloque, no lo duplica).
#   3. Registro en modules-right solo si la clave existe y el nombre
#      no estaba ya (sin reordenar ni eliminar entradas).
#   4. Nunca sobrescribe el fichero completo.
# Si waybar no esta instalado o no tiene config, se omite sin abortar.

# Helper: backup timestamp SOLO si no existe ya uno previo para ese
# fichero. Asi una re-instalacion no acumula decenas de backups.
waybar_backup_once() {
    local target="$1"
    [[ -f "$target" ]] || return 0
    if ! ls "${target}".cachyos.bak-* >/dev/null 2>&1; then
        cp -p "$target" "${target}.cachyos.bak-$(date +%s)"
    fi
}

# Helper: inserta (o reemplaza) un bloque delimitado por marcadores.
#   $1=snippet_path $2=target_path $3=open_marker $4=close_marker
#   $5=before_pattern (regex awk; vacio = append al final).
waybar_merge_block() {
    local snippet="$1" target="$2" open_m="$3" close_m="$4" before_pat="${5:-}"
    [[ -f "$target" ]] || return 1
    local block
    block=$(cat "$snippet")
    if grep -qF -- "$open_m" "$target"; then
        # Marcadores presentes: reemplazar el contenido entre ellos.
        awk \
            -v open_m="$open_m" -v close_m="$close_m" -v block="$block" \
            'BEGIN { in_block = 0 }
             index($0, open_m)  { print open_m; print block; in_block = 1; next }
             index($0, close_m)  { print close_m; in_block = 0; next }
             in_block            { next }
                                { print }' \
            "$target" > "${target}.new" && mv "${target}.new" "$target"
    else
        # Sin marcadores: insertar antes del patron. Si el patron
        # esta vacio, no hay punto de insercion claro: append al
        # final via bloque END.
        awk \
            -v before="$before_pat" -v open_m="$open_m" -v close_m="$close_m" -v block="$block" \
            'BEGIN { inserted = 0; prev = "" }
             {
                 if (!inserted && before != "" && $0 ~ before) {
                     # Insertamos aqui. Si la linea previa es el ultimo
                     # miembro del nivel superior y NO termina ya en
                     # coma, anyadimos coma para mantener JSON valido
                     # al meter el nuevo bloque como hermano.
                     # Casos que NECESITAN coma (valor cerrado, no
                     # apertura):
                     #   }  cierre de objeto
                     #   ]  cierre de array
                     #   "  fin de string escalar (p.ej. "format": "")
                     #   0-9  fin de numero escalar (p.ej. "height": 30)
                     #   true/false/null  fin de literal
                     # Casos que NO la necesitan:
                     #   ,  ya tiene coma
                     #   { o [  apertura de un nuevo contenedor
                     #   linea de comentario // ...
                     rtrim = prev
                     sub(/[[:space:]]+$/, "", rtrim)
                     # Si la linea previa lleva un comentario inline
                     # // ... al final (p.ej. `"height": 30 // px`),
                     # recortarlo SOLO para la decision de coma. El
                     # comentario original NO se modifica en la salida:
                     # el contenido escrito sigue siendo prev intacto.
                     sub(/[[:space:]]+\/\/.*$/, "", rtrim)
                     needs_comma = 0
                     if (rtrim != "" \
                         && rtrim !~ /^[[:space:]]*\/\// \
                         && rtrim !~ /,$/ \
                         && (rtrim ~ /\}$/ || rtrim ~ /\]$/ \
                             || rtrim ~ /"$/ \
                             || rtrim ~ /[0-9]$/ \
                             || rtrim ~ /(true|false|null)$/)) {
                         needs_comma = 1
                     }
                     if (needs_comma) {
                         # Insertar la coma en el offset del contenido
                         # real (el mismo usado para construir rtrim
                         # arriba), NO al final absoluto de prev. Asi,
                         # si la linea lleva un comentario inline
                         # (p.ej. `"height": 30 // px`), la coma cae
                         # tras el contenido (`30`) y el comentario
                         # queda intacto a continuacion: `30, // px`.
                         # Sin comentario, el offset coincide con el
                         # final del contenido y el resultado es
                         # equivalente al previo.
                         split_pos = length(rtrim)
                         prev = substr(prev, 1, split_pos) "," substr(prev, split_pos + 1)
                     }
                     print prev
                     print open_m
                     print block
                     print close_m
                     print ""
                     prev = $0
                     inserted = 1
                     next
                 }
                 if (!inserted) {
                     if (prev != "") print prev
                     prev = $0
                 } else {
                     print
                 }
             }
             END {
                 if (!inserted) {
                     if (prev != "") print prev
                     print open_m
                     print block
                     print close_m
                 } else {
                     print prev
                 }
             }' \
            "$target" > "${target}.new" && mv "${target}.new" "$target"
    fi
}

# Helper: anade un nombre al array modules-right si la clave existe y
# el nombre no estaba. Operacion idempotente. Asume el array en una
# sola linea (patron tipico en configs omarchy); si modules-right no
# existe, no se crea (el usuario tendria otra estructura).
#
# Limitacion: el sed solo opera cuando el array y su ] de cierre
# estan en la misma linea. Si el array esta repartido en varias
# lineas, el patron no matchea y la funcion NO registra el modulo.
# En ese caso se avisa por stderr para que el usuario lo agregue a
# mano (no es obligatorio soportar multilinea automaticamente; SI es
# obligatorio dejar de fallar en silencio).
waybar_register_module() {
    local target="$1" module_name="$2"
    [[ -f "$target" ]] || return 0
    grep -q '"modules-right"' "$target" || return 0
    if grep '"modules-right"' "$target" | grep -qF -- "\"$module_name\""; then
        return 0
    fi
    # Capturar el hash antes/despues para detectar si el sed produjo
    # algun cambio efectivo. Si no cambio nada, probablemente el array
    # esta repartido en varias lineas y el patron de una sola linea
    # no encontro nada que sustituir.
    local before_hash after_hash
    before_hash=$(grep -F '"modules-right"' "$target" | sort | md5sum)
    # Reemplazar el ultimo ] de la linea modules-right por ", "<name>"]".
    # El JSONC permite coma final tras ], asi que conservamos cualquier
    # coma que hubiera (captura con \(,*\)$). Usamos | como delimiter
    # porque module_name puede contener "/" (custom/cachyos-update).
    sed -i "/\"modules-right\"/ s|\]\(,*\)\$|, \"${module_name}\"]\1|" "$target"
    after_hash=$(grep -F '"modules-right"' "$target" | sort | md5sum)
    if [[ "$before_hash" == "$after_hash" ]]; then
        echo "AVISO waybar: no se pudo registrar \"${module_name}\" en modules-right de forma automatica." >&2
        echo "  El array modules-right de $target parece estar repartido en varias lineas," >&2
        echo "  algo que este script no soporta. Anyade manualmente \"${module_name}\" al" >&2
        echo "  array modules-right en $target para que el modulo sea visible." >&2
    fi
}

WAYBAR_CONFIG="$TARGET_HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$TARGET_HOME/.config/waybar/style.css"
WAYBAR_CONFIG_SNIPPET="$REPO_DIR/waybar/config-snippet.jsonc"
WAYBAR_STYLE_SNIPPET="$REPO_DIR/waybar/style-snippet.css"

if [[ -f "$WAYBAR_CONFIG" ]] && [[ -f "$WAYBAR_CONFIG_SNIPPET" ]]; then
    waybar_backup_once "$WAYBAR_CONFIG"
    # Sustituir @SCRIPTS_DIR@ por la ruta real del repo en el snippet.
    waybar_snippet_rendered=$(mktemp)
    sed "s|@SCRIPTS_DIR@|$SCRIPTS_DIR|g" "$WAYBAR_CONFIG_SNIPPET" > "$waybar_snippet_rendered"
    # Registrar el modulo en modules-right ANTES de insertar el
    # bloque: asi el grep posterior no confunde la clave top-level
    # recien insertada con una entrada del array.
    waybar_register_module "$WAYBAR_CONFIG" "custom/cachyos-update"
    # Insertar el bloque antes de la } de cierre del objeto raiz.
    waybar_merge_block "$waybar_snippet_rendered" "$WAYBAR_CONFIG" \
        "// >>> cachyos-setup update module >>>" \
        "// <<< cachyos-setup update module <<<" \
        '^}$'
    rm -f "$waybar_snippet_rendered"
    echo "Modulo waybar CachyOS Update fusionado en $WAYBAR_CONFIG."
fi

if [[ -f "$WAYBAR_STYLE" ]] && [[ -f "$WAYBAR_STYLE_SNIPPET" ]]; then
    waybar_backup_once "$WAYBAR_STYLE"
    # En CSS no hay un punto de insercion claro: append al final.
    waybar_merge_block "$WAYBAR_STYLE_SNIPPET" "$WAYBAR_STYLE" \
        "/* >>> cachyos-setup update module >>> */" \
        "/* <<< cachyos-setup update module <<< */" \
        ""
    echo "Estilo waybar CachyOS Update fusionado en $WAYBAR_STYLE."
fi

# Recargar waybar si esta corriendo, para que el nuevo modulo sea
# visible sin re-login. Best-effort: si no hay bus de usuario o
# waybar no corre, se omite.
if [[ -f "$WAYBAR_CONFIG" ]]; then
    runuser -u "$TARGET_USER" -- pkill -USR2 waybar 2>/dev/null || true
fi

# ---- user-level units (omarchy-check) ----
mkdir -p "$SYSTEMD_USER_DIR"
for unit in "$REPO_DIR"/systemd/user/*.service "$REPO_DIR"/systemd/user/*.timer; do
    [ -e "$unit" ] || continue
    name=$(basename "$unit")
    target="$SYSTEMD_USER_DIR/$name"
    rm -f "$target"
    sed "s|@SCRIPTS_DIR@|$SCRIPTS_DIR|g" "$unit" > "$target"
done
# These calls may fail when there is no active user systemd session (e.g. running
# via sudo without a logged-in desktop session). The unit files are already installed
# correctly in ~/.config/systemd/user/. To activate them manually from a user
# session run:
#   systemctl --user daemon-reload
#   systemctl --user enable --now omarchy-check.timer
systemctl --user --machine="$TARGET_USER@.host" daemon-reload || true
systemctl --user --machine="$TARGET_USER@.host" enable --now omarchy-check.timer || true

# ---- system-level units (cachyos-update, run as root) ----
USER_UID="$(id -u "$TARGET_USER")"
for unit in "$REPO_DIR"/systemd/system/*.service "$REPO_DIR"/systemd/system/*.timer; do
    [ -e "$unit" ] || continue
    name=$(basename "$unit")
    target="$SYSTEMD_SYSTEM_DIR/$name"
    sudo sed -e "s|@SCRIPTS_DIR@|$SCRIPTS_DIR|g" \
              -e "s|@USER@|$TARGET_USER|g" \
              -e "s|@UID@|$USER_UID|g" "$unit" | sudo tee "$target" > /dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable --now cachyos-update.timer

# ---- Bootloader: NVIDIA KMS cmdline ----
# Activa nvidia-drm.modeset=1 de forma persistente via drop-in de
# limine-entry-tool. Idempotente: solo regenera limine.conf si el
# drop-in cambia. En maquinas sin Limine se omite sin abortar.
if command -v limine-update >/dev/null 2>&1; then
    src="$REPO_DIR/etc/limine-entry-tool.d/nvidia.conf"
    dst="/etc/limine-entry-tool.d/nvidia.conf"
    if [ -f "$src" ]; then
        sudo install -d -m 0755 /etc/limine-entry-tool.d
        if ! sudo cmp -s "$src" "$dst"; then
            sudo install -m 0644 "$src" "$dst"
            sudo limine-update
            echo "Drop-in NVIDIA KMS instalado y limine.conf regenerado."
        else
            echo "Drop-in NVIDIA KMS ya actualizado; nada que hacer."
        fi
    else
        echo "Drop-in NVIDIA KMS no presente en el repo; se omite."
    fi
else
    echo "limine-update no encontrado; se omite el drop-in NVIDIA KMS."
fi

echo "Listo. Timers:"
echo "  systemctl --user list-timers      (omarchy-check)"
echo "  systemctl list-timers --all       (cachyos-update)"
if ! command -v needrestart >/dev/null 2>&1; then
    cat <<'EOF'

AVISO: needrestart no esta instalado.
  Para detectar servicios pendientes de reiniciar tras actualizar
  (recomendado): yay -S needrestart
  Sin el, update-system.sh funciona identico, simplemente no avisa de
  procesos con .so antiguas en memoria.
EOF
fi
