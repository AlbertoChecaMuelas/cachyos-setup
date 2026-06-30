# cachyos-setup

Scripts de automatización para CachyOS + omarchy.

## Qué hace

- Actualización semanal del sistema (paquetes oficiales y AUR) con notificaciones de escritorio.
- Aviso de reinicio si se actualiza el kernel o nvidia.
- Aviso de nueva versión de omarchy-on-cachyos (no se instala sola).
- Resumen persistente: si el timer corre sin sesión gráfica, la notificación queda guardada y se muestra al iniciar sesión.

## Requisitos

- CachyOS
- Hyprland + mako (servidor de notificaciones)
- [aurutils](https://aur.archlinux.org/packages/aurutils/) — instalado automáticamente por `./install.sh` desde los repos oficiales.
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

`./install.sh` configura de forma idempotente:

- aurutils + repo local `/var/lib/aur-repo/` con base de datos `aur-local`.
- Sección `[aur-local]` en `/etc/pacman.conf` apuntando a `file:///var/lib/aur-repo`.
- Script de autostart `~/.config/autostart/cachyos-update-summary.desktop`
  que muestra el resumen pendiente al iniciar sesión.

## Uso manual

```bash
sudo systemctl start cachyos-update.service
```

(También puedes lanzar el script directamente: `sudo ./scripts/update-system.sh`).

## Actualización AUR automática

El ciclo de actualización usa `aur sync` (aurutils) para compilar los
paquetes AUR y depositarlos en el repo local `/var/lib/aur-repo/`.
Después, el `pacman -Syu` resuelve e instala tanto los oficiales
como los AUR en un solo paso. No hace falta ejecutar `yay -Syu`
manualmente.

La compilación se hace como `$TARGET_USER` (no como root) para que
`aur` no se queje, y se ejecuta ANTES de `pacman -Syu` para que el
repo local esté actualizado cuando pacman resuelva.

## Logs

- Ejecución automática (timer): `/var/lib/cachyos-setup/`
- Ejecución manual con `sudo` en terminal: `/root/.local/state/cachyos-setup/`

Los logs se acumulan entre ejecuciones: cada ejecución antepone una
cabecera con fecha (`===== Actualización: ... =====` para el sistema,
`===== Check omarchy: ... =====` para omarchy). Para limpiarlos:

```bash
sudo rm /var/lib/cachyos-setup/*.log
rm -f /root/.local/state/cachyos-setup/*.log
```

Adicionalmente, cada ejecución del actualizador deja un resumen
persistente en `last-summary.txt` dentro de `STATE_DIR`. Si la
notificación no pudo entregarse (por ejemplo, sin sesión gráfica),
un script de autostart la muestra al iniciar sesión y borra el
fichero para no repetirla.

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

# Eliminar autostart del resumen de updates
rm -f ~/.config/autostart/cachyos-update-summary.desktop

# Eliminar config de aurutils (repo local + entrada en pacman.conf)
sudo rm -rf /var/lib/aur-repo
sudo sed -i '/^\[aur-local\]/,/^$/d' /etc/pacman.conf
sudo pacman -Rns --noconfirm aurutils 2>/dev/null || true

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
  `sudo` corre como root y escribe a `/root/.local/state/cachyos-setup/`.
- **`omarchy-check.{service,timer}`**: servicio **user-level** desde
  `~/.config/systemd/user/`. No necesita root (solo lee un repo git y
  compara con upstream).
- **`cachyos-update-summary.desktop`**: entrada de autostart en
  `~/.config/autostart/` que muestra el resumen pendiente al iniciar
  sesión gráfica (y lo borra tras mostrarlo).

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
