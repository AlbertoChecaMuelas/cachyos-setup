# Registro de cambios

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/)
y este proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [Unreleased]

### Added
- notificar listado de paquetes relevantes al actualizar (kernel, nvidia, systemd, glibc, openssl, mesa, xorg-server, wayland)
- detectar servicios pendientes de reiniciar via `needrestart` (AUR opcional) tras actualizar
- log acumulativo entre ejecuciones, con cabecera por fecha
- aviso en `install.sh` si `needrestart` no esta instalado
- variables de entorno `OMARCHY_DIR` y `OMARCHY_URL` para apuntar al fork local y al upstream seguido
- seccion "Personalizacion" en README con tabla de variables

### Changed
- `cachyos-update.{service,timer}` pasa a ser **system-level** (corre como root desde `/etc/systemd/system/`) en lugar de user-level. Esto evita el problema PAM/sudo/TTY que bloqueaba la automatizacion en algunos sistemas.
- `update-system.sh` ya no invoca `sudo` para `pacman`/`yay`/`needrestart`; asume que se ejecuta como root (bien desde el timer, bien desde la terminal con `sudo`).
- logs del timer semanal van a `/var/lib/cachyos-setup/`; logs de invocacion manual mantienen `~/.local/state/cachyos-setup/`.
- reorganizar `systemd/` en `systemd/user/` y `systemd/system/` para reflejar el modelo mixto.
- estructura del sudoers: usar `@USER@` placeholder resuelto por `install.sh` via `sed` + `visudo -cf` sobre fichero temporal.
- README y PATH de notificaciones asumen que el script puede ejecutarse con TTY.

### Fixed
- notification suprimida cuando `pacman -Syu` no actualiza nada (antes enviaba "0 paquetes actualizados" como ruido).
- `omarchy-check` escribe `OK: al dia` en log cuando la version local coincide con upstream, sin enviar notify.
- handle sudoers generico via `@USER@` para que la instalacion sea portable entre usuarios.
- resolver problema PAM `pam_unix.so try_first_pass nullok` que bloqueaba automation del timer (con refactor system-level).

### Removed
- `sudoers/cachyos-pacman` ya no es necesario: el servicio system-level corre como root directo. Se mantiene el archivo plantilla por compatibilidad hacia atras pero `install.sh` no lo instala.

### Migration
- Las instalaciones existentes detectan automaticamente `~/.config/systemd/user/cachyos-update.timer` y lo desactivan/eliminan al ejecutar `./install.sh` sobre esta version.

