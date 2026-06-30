# Registro de cambios

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/)
y este proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [Unreleased]

### Added
- notif. utiles, logs acumulativos, AUR manual y service system-level
- notificar listado de paquetes relevantes al actualizar (kernel, nvidia, systemd, glibc, openssl, mesa, xorg-server, wayland)
- detectar servicios pendientes de reiniciar via `needrestart` (AUR opcional) tras actualizar
- log acumulativo entre ejecuciones, con cabecera por fecha
- aviso en `install.sh` si `needrestart` no esta instalado
- variables de entorno `OMARCHY_DIR` y `OMARCHY_URL` para apuntar al fork local y al upstream seguido
- seccion "Personalizacion" en README con tabla de variables
- **AUR automatico** integrado en el ciclo de actualizacion: `aur sync` (aurutils) compila los paquetes AUR y los deposita en un repo local `/var/lib/aur-repo/`; `pacman -Syu` los resuelve e instala junto a los oficiales.
- **Resumen persistente** (`$STATE_DIR/last-summary.txt`) escrito SIEMPRE al final de la corrida, con independencia de si `notify-send` tuvo exito. Un script de autostart (`scripts/show-update-summary.sh`) lo muestra al iniciar sesion grafica y luego lo borra.

### Changed
- `cachyos-update.{service,timer}` pasa a ser **system-level** (corre como root desde `/etc/systemd/system/`) en lugar de user-level. Esto evita el problema PAM/sudo/TTY que bloqueaba la automatizacion en algunos sistemas.
- `update-system.sh` ya no invoca `sudo` para `pacman`/`aur`/`needrestart`; asume que se ejecuta como root (bien desde el timer, bien desde la terminal con `sudo`).
- logs del timer semanal van a `/var/lib/cachyos-setup/`; logs de invocacion manual con `sudo` van a `/root/.local/state/cachyos-setup/`.
- reorganizar `systemd/` en `systemd/user/` y `systemd/system/` para reflejar el modelo mixto.
- estructura del sudoers: usar `@USER@` placeholder resuelto por `install.sh` via `sed` + `visudo -cf` sobre fichero temporal.
- README y PATH de notificaciones asumen que el script puede ejecutarse con TTY.

### Fixed
- activar nvidia-drm.modeset=1 via drop-in limine-entry-tool
- usar TARGET_USER/HOME bajo sudo y documentar AUR automático
- configurar AUR automático y permisos de resumen
- corregir instalación aurutils y setup repo local
- corregir bugs críticos pre-merge y añadir AUR automático con aurutils
- ampliar NOPASSWD para yay sin TTY (#7)
- Activar `nvidia-drm.modeset=1` de forma persistente via drop-in de `limine-entry-tool` (fix pantalla negra en soft-reboot con `nvidia-open`).
- notification suprimida cuando `pacman -Syu` no actualiza nada (antes enviaba "0 paquetes actualizados" como ruido).
- `omarchy-check` escribe `OK: al dia` en log cuando la version local coincide con upstream, sin enviar notify.
- handle sudoers generico via `@USER@` para que la instalacion sea portable entre usuarios.
- resolver problema PAM `pam_unix.so try_first_pass nullok` que bloqueaba automation del timer (con refactor system-level).
- **bug critico de parseo**: `reboot_needed` y el conteo de paquetes (`total`, `relevant`, `rest`) ahora se calculan sobre `$STATE_DIR/current-run.log` (truncado por corrida) en vez de sobre `$LOG_FILE` (acumulativo historico). Antes, despues de actualizar linux/nvidia una vez, `reboot_needed=1` quedaba permanente y el contador de paquetes se inflaba.
- `check-omarchy-update.sh` ahora usa `|| true` en `notify-send` para consistencia con `update-system.sh` y no abortar si la notificacion falla.
- el contador "... y N mas" del mensaje de actualizacion se recalcula como `total - rel_count` (paquetes no relevantes) en vez de `total - rel_shown_n` (que mezclaba relevantes truncados con no relevantes).

### Removed
- `sudoers/cachyos-pacman` eliminado del repo y purgado de despliegues previos por `install.sh` (migracion idempotente). El servicio system-level corre como root directo y no necesita reglas NOPASSWD.
- seccion "Limitacion de paquetes AUR" del README, ya no aplica: AUR se actualiza automaticamente con aurutils.

### Security
- `/etc/sudoers.d/cachyos-pacman` (reglas NOPASSWD para `sudo`/`pacman`/`needrestart`) se elimina automaticamente al ejecutar `./install.sh` sobre esta version. Antes podia persistir en sistemas con despliegues antiguos aunque ya no se usase.

### Migration
- Las instalaciones existentes detectan automaticamente `~/.config/systemd/user/cachyos-update.timer` y lo desactivan/eliminan al ejecutar `./install.sh` sobre esta version.
- `install.sh` purga automaticamente `/etc/sudoers.d/cachyos-pacman` si existe de un despliegue previo.

