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
SCRIPTS_DIR="$REPO_DIR/scripts"
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/install.sh

# ---- State dir para ejecucion manual (user-level) ----
mkdir -p "$TARGET_HOME/.local/state/cachyos-setup"

# ---- State dir para ejecucion automatica (system-level) ----
sudo mkdir -p /var/lib/cachyos-setup
sudo chmod 755 /var/lib/cachyos-setup

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
