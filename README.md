# cachyos-setup

Scripts de automatización para CachyOS + omarchy.

## Qué hace

- Actualización semanal del sistema (paquetes oficiales) con notificaciones de escritorio.
- Aviso de reinicio si se actualiza el kernel o nvidia.
- Aviso de nueva versión de omarchy-on-cachyos (no se instala sola).
- Aviso cuando hay paquetes AUR pendientes (la actualización AUR se hace manual con `yay -Syu` desde terminal — ver "Limitación de paquetes AUR" abajo).

## Requisitos

- CachyOS
- Hyprland + mako (servidor de notificaciones)
- yay
- libnotify (notify-send)
- [needrestart](https://aur.archlinux.org/packages/needrestart/) (recomendado,
  AUR) — para notificar servicios pendientes de reiniciar tras actualizar
  `glibc`, `systemd`, etc. Sin él, `update-system.sh` funciona idéntico,
  simplemente no avisa de procesos con `.so` antiguas en memoria. El
  propio `./install.sh` avisa al final si no lo detecta instalado.

## Instalación

```bash
git clone https://github.com/AlbertoChecaMuelas/cachyos-setup.git
cd cachyos-setup
./install.sh
```

## Uso manual

```bash
sudo systemctl start cachyos-update.service
```

(También puedes lanzar el script directamente: `sudo ./scripts/update-system.sh`).

Para actualizar paquetes AUR manualmente (la actualización automática
no los cubre; ver abajo):

```bash
sudo yay -Syu
```

## Limitación de paquetes AUR

El timer automático (`cachyos-update.timer`) solo actualiza paquetes
oficiales con `pacman -Syu`. Los paquetes AUR se quedan desatendidos
por una razón técnica: `yay` invoca `sudo` internamente para
instalar los paquetes AUR compilados, y la mayoría de configuraciones
PAM (en concreto `pam_unix.so try_first_pass nullok` en
`/etc/pam.d/system-auth`) fuerzan conversation de password incluso
con reglas NOPASSWD, lo cual falla en contextos sin TTY como un
servicio systemd.

Si tu sistema tiene una configuración PAM más permisiva, puedes
intentar añadir a `update-system.sh` un best-effort que pase la
prueba, pero por defecto el proyecto asume que el timer no puede
manejar AUR de forma fiable y obliga al usuario a correr `yay -Syu`
manualmente desde terminal interactiva (donde yay sí funciona).

Cuando la actualización automática se ejecuta y detecta que AUR no
se pudo actualizar, envía una notificación avisándote. Ejecutar
`sudo yay -Syu` desde una terminal completa el ciclo.

## Logs

`~/.local/state/cachyos-setup/`

Los logs se acumulan entre ejecuciones: cada ejecución antepone una
cabecera con fecha (`===== Actualización: ... =====` para el sistema,
`===== Check omarchy: ... =====` para omarchy). Para limpiarlos:

```bash
rm ~/.local/state/cachyos-setup/*.log
```

## Personalización

Estos valores tienen defaults portables pero puedes sobreescribirlos
editando los units instalados en `~/.config/systemd/user/` y reejecutando
`./install.sh`:

| Variable | Default | Override |
|---|---|---|
| `OMARCHY_DIR` | `%h/repos/forks/omarchy-on-cachyos` | ruta local de tu fork de omarchy |
| `OMARCHY_URL` | `https://github.com/mroboff/omarchy-on-cachyos.git` | URL del upstream que quieres seguir |

Tras `./install.sh`, edita `~/.config/systemd/user/omarchy-check.service`,
cambia las líneas `Environment=OMARCHY_DIR=` y `Environment=OMARCHY_URL=`
a tu ruta/URL, y ejecuta `systemctl --user daemon-reload`.

`OMARCHY_DIR` también se puede sobreescribir en tiempo de ejecución
exportando la variable antes de invocar el script manualmente.

## Desinstalar

```bash
# Detener y deshabilitar los timers
sudo systemctl disable --now cachyos-update.timer
systemctl --user disable --now omarchy-check.timer

# Eliminar las units instaladas
sudo rm /etc/systemd/system/cachyos-update.service \
       /etc/systemd/system/cachyos-update.timer
rm -f ~/.config/systemd/user/omarchy-check.service \
      ~/.config/systemd/user/omarchy-check.timer
sudo systemctl daemon-reload
systemctl --user daemon-reload

# Eliminar sudoers (legacy)
sudo rm /etc/sudoers.d/cachyos-pacman

# Eliminar logs (opcional)
rm -rf ~/.local/state/cachyos-setup
sudo rm -rf /var/lib/cachyos-setup
```

> Nota: las versiones previas a `feature/improved-update-notifications`
> usaban solo `~/.config/systemd/user/cachyos-update.{service,timer}` y
> `/etc/sudoers.d/cachyos-pacman`. Esos archivos se eliminan
> automáticamente al ejecutar `./install.sh` sobre la nueva versión
> (migración integrada).

## Modelo de ejecución

- **`cachyos-update.{service,timer}`**: servicio **system-level** que
  corre como root desde `/etc/systemd/system/`. No usa sudo. Los logs
  del timer van a `/var/lib/cachyos-setup/`. La invocación manual con
  `sudo` sigue funcionando y escribe a `~/.local/state/cachyos-setup/`.
- **`omarchy-check.{service,timer}`**: servicio **user-level** desde
  `~/.config/systemd/user/`. No necesita root (solo lee un repo git y
  compara con upstream).

## Notas de mantenimiento

- Tras editar un fichero `.service` o `.timer` del repo, vuelve a ejecutar
  `./install.sh` para regenerar los units reales en `~/.config/systemd/user/`
  con la ruta absoluta correcta del clon.

### Desinstalar units

```bash
systemctl --user disable --now cachyos-update.timer omarchy-check.timer
rm -f ~/.config/systemd/user/cachyos-update.service \
      ~/.config/systemd/user/cachyos-update.timer \
      ~/.config/systemd/user/omarchy-check.service \
      ~/.config/systemd/user/omarchy-check.timer
systemctl --user daemon-reload
```
