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

El visor muestra dos bloques:

- **Última actualización del sistema** (cachyos-update): fecha,
  resultado (`success`/`partial`/`failure`), motivo si lo hubo,
  paquetes actualizados y si conviene reiniciar.
- **Comprobación de omarchy-on-cachyos**: fecha de la última
  comprobación, versiones local y remota, y si hay actualización
  pendiente. Si el script `check-omarchy-update.sh` aún no ha
  escrito su estado, el bloque aparece como "aún no comprobado".

Al pie del visor se recuerda explícitamente que la instalación de
una nueva versión de omarchy es **manual** y **fuera de este repo**:
aquí solo se informa del estado.

Sin registro todavía, imprime "No hay ningún registro de actualización
todavía." para el bloque de cachyos-update y sale sin error.

#### Acciones interactivas en el visor

Dentro de la ventana flotante del visor se muestra un prompt:

    [c] Comprobar omarchy ahora   [u] Actualizar cachyos ahora   [r] Reinstalar fork omarchy   [Enter] Cerrar >

- `c` ejecuta `check-omarchy-update.sh` directamente (user-level, sin
  `pkexec`: el servicio `omarchy-check` es user-level y solo hace
  lectura de red), refresca `omarchy-check.env` con el resultado de la
  comprobación y re-renderiza el bloque de omarchy en la **misma
  ventana** sin cerrarla.
- `u` lanza la actualización del sistema reutilizando `update-now.sh`
  **inline** dentro de la misma ventana flotante. La acción escala
  privilegios con el `pkexec` ya existente de `update-now.sh` (sin
  añadir un `pkexec` nuevo ni relajar el polkit) y muestra el progreso
  en vivo del `oneshot`. Al terminar, el visor re-renderiza el bloque
  de "Última actualización" — `update-now.sh` salta su pausa final de
  cierre (variable de entorno `CACHYOS_SKIP_PAUSE`) para devolver el
  control al bucle.
- `r` **reinstalar el fork `omarchy-on-cachyos`** vía el instalador del
  propio fork (`$OMARCHY_DIR/bin/install-omarchy-on-cachyos.sh`,
  interactivo). **Solo está activa cuando el fork declara soportar
  exactamente la versión base disponible** (ver gating más abajo); en
  cualquier otro caso la acción aparece visible pero deshabilitada con
  un mensaje explicativo, y nunca invoca `omarchy-update` nativo.
- Pulsar `Enter` (o dejar la entrada vacía) cierra la ventana.

> Cambio de diseño: el visor, hasta ahora de solo lectura, pasa a
> poder disparar acciones que escalan privilegios. **No se añade
> `pkexec` nuevo**: se reutiliza el de `update-now.sh`, que ya está
> sujeto a la regla polkit
> `etc/polkit-1/rules.d/49-cachyos-update.rules`. La superficie de
> privilegios no se amplía: el click-derecha del módulo waybar (que
> ya invocaba `update-now.sh`) y la tecla `u` del visor comparten la
> misma acción y el mismo `pkexec`. La tecla `r` no escala privilegios
> por sí misma (el instalador del fork gestiona sus propios sudo).

#### Estado durable de omarchy (`omarchy-check.env`)

`check-omarchy-update.sh` escribe, al final de cada comprobación, un
fichero sourceable en el state dir user-level
(`$HOME/.local/state/cachyos-setup/omarchy-check.env`) con estas
**8 claves**, emitidas SIEMPRE (incluidas las ramas de early-exit del
script):

- `OMARCHY_CHECK_TIMESTAMP` (fecha ISO-8601 de la comprobación).
- `OMARCHY_LOCAL_VERSION` (versión local, vacía si no hay tag).
- `OMARCHY_REMOTE_VERSION` (última versión upstream del fork).
- `OMARCHY_UPDATE_AVAILABLE` (`true`/`false`, indica si hay un tag más
  nuevo en el upstream).
- `OMARCHY_BASE_SUPPORTED` — versión base de omarchy que el fork
  declara soportar (texto plano en
  `$OMARCHY_DIR/SUPPORTED_OMARCHY_VERSION`, normalizada sin prefijo
  `v`).
- `OMARCHY_BASE_AVAILABLE` — versión base disponible = último tag de
  `basecamp/omarchy` (normalizada sin prefijo `v`).
- `OMARCHY_BASE_INSTALLED` — versión base instalada en
  `~/.local/share/omarchy/version` (solo contexto informativo; no
  participa en la decisión del gate).
- `OMARCHY_REINSTALL_ALLOWED` (`true`/`false`) — decisión computada del
  gate de reinstalación (ver siguiente sección).

La escritura es atómica (temporal + `mv`) y se ejecuta siempre, incluso
en las ramas de borde (directorio local inexistente, upstream ilegible):
el env queda completo y sourceable en cualquier estado, con
`OMARCHY_UPDATE_AVAILABLE="false"` y `OMARCHY_REINSTALL_ALLOWED="false"`
cuando no se puede determinar. Este fichero es **adicional** al log
append-only `omarchy-check.log`, que se mantiene intacto.

#### Gating de reinstalación del fork

La acción `r` del visor está **gated** por la versión base que el fork
declara soportar. El contrato es:

- **Fuente de la versión soportada:** el fork publica en su raíz un
  fichero de texto plano de una sola línea llamado
  `SUPPORTED_OMARCHY_VERSION`, con la versión normalizada sin prefijo
  `v` (p. ej. `3.8.3`). `check-omarchy-update.sh` lo lee del clon local
  `$OMARCHY_DIR` con `head -n1` — **nunca** se hace `source` del
  fichero, para no ejecutar código del fork.
- **Versión disponible:** último tag de `basecamp/omarchy` (upstream
  de omarchy).
- **Regla del gate:** `OMARCHY_REINSTALL_ALLOWED` se computa a `true`
  solo cuando la versión declarada por el fork es exactamente igual a
  la última versión disponible. La versión instalada es solo contexto
  informativo.
- **Fallback seguro:** si `SUPPORTED_OMARCHY_VERSION` no existe o está
  vacío en el fork, o si no se puede leer la versión disponible,
  entonces `OMARCHY_REINSTALL_ALLOWED="false"` y la acción aparece
  deshabilitada. **Nunca** se ofrece reinstalación activa con datos
  incompletos.

Por diseño, mientras el fork no declare su versión soportada
(independiente del repo `cachyos-setup`), la acción `r` está
deshabilitada y el visor lo indica. Habilitarla requiere primero
actualizar el fork a una versión que coincida con la base disponible
(`SUPPORTED_OMARCHY_VERSION` = último tag de `basecamp/omarchy`), paso
que se hace **fuera de este repo**.

> Limitación preexistente (no abordada aquí): `check-omarchy-update.sh`
> detecta "actualización del fork disponible" comparando TAGS. Si el
> HEAD del fork va por delante del último tag, la herramienta puede
> infra-reportar; es comportamiento existente, no se corrige en este
> plan.

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
