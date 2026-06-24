# cachyos-setup

Scripts de automatización para CachyOS + omarchy.

## Qué hace

- Actualización semanal del sistema (pacman + yay) con notificaciones de escritorio.
- Aviso de reinicio si se actualiza el kernel o nvidia.
- Aviso de nueva versión de omarchy-on-cachyos (no se instala sola).

## Requisitos

- CachyOS
- Hyprland + mako (servidor de notificaciones)
- yay
- libnotify (notify-send)

## Instalación

```bash
git clone https://github.com/AlbertoChecaMuelas/cachyos-setup.git
cd cachyos-setup
./install.sh
```

## Uso manual

```bash
systemctl --user start cachyos-update.service
```

## Logs

`~/.local/state/cachyos-setup/`

## Desinstalar

```bash
systemctl --user disable --now cachyos-update.timer omarchy-check.timer
sudo rm /etc/sudoers.d/cachyos-pacman
```
