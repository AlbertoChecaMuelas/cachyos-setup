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
- [aurutils](https://aur.archlinux.org/packages/aurutils/) — instalado automáticamente por `./install.sh`, compilado automáticamente desde AUR (vía yay/paru, o makepkg si no hay helper).
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
sudo ./install.sh
```

`./install.sh` configura de forma idempotente:

- aurutils + repo local `/var/lib/aur-repo/` con base de datos `aur-local`.
- Sección `[aur-local]` en `/etc/pacman.conf` apuntando a `file:///var/lib/aur-repo`.
- Script de autostart `~/.config/autostart/cachyos-update-summary.desktop`
  que muestra el resumen pendiente al iniciar sesión.

## Primeros pasos

Después de clonar e instalar, registra en el repo local los paquetes AUR
que ya tengas instalados para que el servicio `cachyos-update` los
gestione automáticamente a partir de ahora:

1. Ejecuta el instalador:

   ```bash
   sudo ./install.sh
   ```

2. Lista los paquetes AUR ya presentes en el sistema:

   ```bash
   pacman -Qm
   ```

3. Regístralos en el repo local de aurutils (una sola vez por paquete;
   `aur sync` los construye y los añade a `/var/lib/aur-repo/` para que
   `pacman -Syu` los actualice como cualquier oficial):

   ```bash
   aur sync --noconfirm --no-view paquete1 paquete2 ...
   ```

   (puedes pasar varios paquetes en una sola invocación).

Tras esto, `systemctl list-timers --all` mostrará el timer
`cachyos-update.timer` corriendo cada domingo y los AUR se actualizarán
junto con el sistema.

## Migración desde versión anterior

Si ya tenías una versión previa con `cachyos-update.{service,timer}`
**user-level** y `/etc/sudoers.d/cachyos-pacman`:

1. Actualiza el repo:

   ```bash
   git pull
   ```

2. Ejecuta el instalador (purga el sudoers legacy, desactiva y borra el
   timer user-level antiguo y despliega la versión system-level):

   ```bash
   sudo ./install.sh
   ```

3. Verifica que el timer user-level antiguo ya no existe:

   ```bash
   systemctl --user list-timers | grep cachyos-update || echo "OK: timer user-level eliminado"
   ```

   No debe aparecer ningún `cachyos-update.timer` en la salida.

4. Registra los paquetes AUR en el repo local (mismo procedimiento que
   en Primeros pasos):

   ```bash
   pacman -Qm
   aur sync --noconfirm --no-view paquete1 paquete2 ...
   ```

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

## Gestión de paquetes AUR

`aurutils` **no descubre automáticamente** los paquetes AUR instalados en el
sistema: hay que registrarlos explícitamente en el repo local una sola vez.
A partir de ese momento el servicio `cachyos-update` los actualizará cada
domingo sin intervención manual.

### Primera vez (instalación nueva o migración)

Localiza los paquetes AUR que ya tienes instalados y añádelos al repo local:

```bash
# Ver qué paquetes AUR tienes instalados
pacman -Qm

# Añadirlos al repo local (una sola vez por paquete)
aur sync --noconfirm --no-view paquete1 paquete2 ...
```

### Añadir un paquete AUR nuevo en el futuro

Instala el paquete con tu helper habitual y luego regístralo en el repo local:

```bash
yay -S nuevo-paquete
aur sync --noconfirm --no-view nuevo-paquete
```

A partir de ese momento el servicio lo actualizará automáticamente cada domingo.

### Ver qué paquetes AUR se están gestionando

```bash
pacman -Sl aur-local
```

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

## Reporte de actualizaciones

Cada ejecución del actualizador (manual o automática) deja un **registro
durable** del resultado, separado del aviso efímero de login. Esto
permite consultar en cualquier momento qué se actualizó, si hubo
fallos y si conviene reiniciar.

### Registro durable (`last-run.env` + `last-run-packages.txt`)

`update-system.sh` escribe, al final de cada corrida, dos ficheros en
`STATE_DIR` (por defecto `/var/lib/cachyos-setup` para el servicio
system-level, o `~/.local/state/cachyos-setup` para la ejecución manual
con `sudo`):

- `last-run.env`: fichero clave=valor sourceable en shell con las
  claves:
  - `LAST_RUN_TIMESTAMP` (fecha ISO-8601 de la corrida).
  - `LAST_RUN_RESULT` (`success` o `failure`).
  - `LAST_RUN_FAIL_REASON` (motivo corto en caso de fallo).
  - `LAST_RUN_REBOOT_NEEDED` (`true` o `false`, derivado del kernel/
    nvidia actualizado).
  - `LAST_RUN_PACKAGE_COUNT` (oficiales + AUR únicos actualizados).
- `last-run-packages.txt`: lista humana de paquetes actualizados (uno
  por línea).

A diferencia de `last-summary.txt` (que el script de autostart borra
tras mostrarlo en el siguiente login), estos dos ficheros **persisten
entre logins** y se sobreescriben en cada nueva corrida.

### Visor `show-last-run.sh`

`scripts/show-last-run.sh` lee el registro durable y lo presenta en
una terminal flotante. Patrón de terminal: usa
`omarchy-launch-floating-terminal-with-presentation` si está
disponible (mismo patrón que el resto del repo); en caso contrario
degrada a `${TERMINAL:-alacritty}`.

Sin registro todavía, imprime "No hay ningún registro de actualización
todavía." y sale sin error.

### Disparo manual `update-now.sh`

`scripts/update-now.sh` lanza una actualización bajo demanda sin
reimplementar la lógica de actualización (que vive en
`update-system.sh`). Lo que hace:

1. Escala privilegios vía `pkexec systemctl start cachyos-update.service`.
2. Sigue el progreso con `journalctl -u cachyos-update.service -f`.
3. Al terminar, lee `last-run.env` y, si `LAST_RUN_REBOOT_NEEDED=true`,
   muestra `>>> Se RECOMIENDA reiniciar el sistema (kernel/nvidia
   actualizados).`

El aviso de reinicio se deriva **exclusivamente** de
`LAST_RUN_REBOOT_NEEDED`. No fuerza reinicio.

### Regla polkit (por qué polkit y no sudoers NOPASSWD)

Escalar privilegios para `systemctl start cachyos-update.service` se
hace vía **polkit** con la regla
`etc/polkit-1/rules.d/49-cachyos-update.rules` (instalada en
`/etc/polkit-1/rules.d/` por `install.sh`). Esa regla autoriza a los
miembros del grupo `wheel` a iniciar **únicamente** la unidad
`cachyos-update.service` (acción `org.freedesktop.systemd1.manage-units`
filtrada por nombre de unidad), sin contraseña.

`install.sh` mantiene la política de **no reintroducir sudoers
NOPASSWD** (de hecho, purga `/etc/sudoers.d/cachyos-pacman` si existe
de instalaciones previas). Polkit es el reemplazo correcto porque
acota la autorización a una sola unidad de systemd, no a sudo genérico.

### Módulo waybar

Si tienes `~/.config/waybar/config.jsonc` desplegado (omarchy o
configuración propia), `install.sh` fusiona de forma **idempotente y no
destructiva** un único módulo `custom/cachyos-update`:

- Click izquierdo: abre el visor `show-last-run.sh` en una terminal
  flotante.
- Click derecho: lanza el disparo manual `update-now.sh` (pide
  contraseña vía polkit).

El merge:

1. Crea un backup con timestamp (`config.jsonc.cachyos.bak-…` y
   `style.css.cachyos.bak-…`) **solo la primera vez** que se toca cada
   fichero.
2. Delimita el bloque insertado con marcadores literales
   `// >>> cachyos-setup update module >>>` / `// <<< ... <<<` (en
   JSONC) y `/* >>> ... >>> */` / `/* <<< ... <<< */` (en CSS). Si los
   marcadores ya están presentes, **reemplaza** el bloque (no
   duplica), por lo que re-ejecutar `install.sh` es seguro.
3. Registra `custom/cachyos-update` en el array `modules-right` solo
   si la clave existe y el nombre no estaba ya, sin reordenar ni
   eliminar módulos preexistentes.
4. Nunca sobrescribe el fichero completo.

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
