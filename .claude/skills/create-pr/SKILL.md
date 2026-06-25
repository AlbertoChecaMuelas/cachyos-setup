---
description: "Orquesta el flujo completo de creación de PR para la rama actual: refresco del changelog, descripción de PR auto-generada y apertura de la PR con gh. Úsalo cuando el usuario pida crear o abrir una pull request ('crea la PR', 'abre el pull request', 'create the PR', 'crea la MR', 'abre el merge request'). Requiere gh en PATH, un remote origin y una rama que no sea master/main."
argument-hint: "[base-branch]"
---

# Create PR — flujo de release orquestado

Precondiciones (si alguna falla, informar al usuario y parar):
(a) `gh` está en PATH y autenticado; (b) el repo tiene un remote `origin`; (c) la rama actual no es `master`/`main`; (d) la rama actual está pusheada a `origin` (`gh pr create` no puede abrir una PR de una rama que no existe en el remoto).

Ejecuta esta secuencia en orden, completamente automática — sin pedir entrada manual al usuario. `<base>` es la rama destino de la PR (`$1`, por defecto `master`).

1. Invocar `/update-changelog --branch <base>`. En modo branch-scoped, el skill delega en `tools/release/update-changelog.sh`, que clasifica los commits de la rama (feat/feature → Añadido, fix → Corregido, refactor/perf/docs → Cambiado, chore/build/ci/other → omitido) y ANTEPONE un bloque `### Añadido/Cambiado/Corregido` bajo `## [Unreleased]` en CHANGELOG.md, deduplicando bullets en cada subsección (idempotente: re-ejecutar `/create-pr` no duplica contenido en el changelog). La sección NO se renombra aquí — tras el merge de la PR y la creación del tag, la CI `auto-tag` la cierra como `[vX.Y.Z] - YYYY-MM-DD` y pushea el commit de cierre a `master`.

2. Delegar a `applier` la ejecución de `$(git rev-parse --show-toplevel)/tools/release/commit-changelog.sh`. El script stagea `CHANGELOG.md` y crea el commit `docs(changelog): update [Unreleased] for upcoming PR`. Si `commit-changelog.sh` termina con exit 3 (nada que stagear — CHANGELOG.md sin cambios), no hay commit de changelog que hacer; saltar directamente al paso 3.

3. Invocar `/pr-description` para (re)generar `PR-DESCRIPTION.md` a partir del historial actualizado (el commit de changelog queda incluido en el rango de diff). Tras recibir el output del skill, delegar a `applier` una escritura literal y verbatim de ese output en `PR-DESCRIPTION.md` en la raíz del repo. No parafrasear ni reformatear el contenido. `PR-DESCRIPTION.md` es un artefacto de trabajo y NO debe commitearse NUNCA: antes o justo después de la escritura, asegurar que el `.gitignore` del repo contiene la línea `PR-DESCRIPTION.md` (crear el fichero o añadir la línea si falta; idempotente — no duplicar); si `git ls-files --error-unmatch PR-DESCRIPTION.md` indica que el fichero está trackeado, delegar a `applier` un `git rm --cached PR-DESCRIPTION.md` para que la regla de ignore tome efecto.

4. Delegar a `applier` la ejecución de `$(git rev-parse --show-toplevel)/tools/release/create-pr.sh` en lugar de improvisar con `gh pr create` directo o llamadas REST.

5. Si `create-pr.sh` termina con exit 3 (sello obsoleto respecto a HEAD): re-invocar `/pr-description`, delegar la re-escritura literal de `PR-DESCRIPTION.md` a `applier`, y re-delegar `create-pr.sh` a `applier` una única vez más.

El skill nunca ejecuta `git push`; el push es responsabilidad del usuario. La rama debe estar pusheada a `origin` ANTES de abrir la PR. Como el paso 2 crea un commit de changelog local, si `create-pr.sh` sale con exit 2 («push first»), parar e indicar al usuario que ejecute `git push origin <branch>` y vuelva a invocar `/create-pr`. Re-invocar es seguro e idempotente: la actualización del changelog deduplica bullets en cada ejecución y no añade entradas repetidas en `[Unreleased]`. Tras el squash-merge a `master`, la CI `auto-tag` crea y pushea el tag, luego cierra `[Unreleased]` como `[vX.Y.Z] - YYYY-MM-DD` y pushea ese commit de seguimiento a `master`.
