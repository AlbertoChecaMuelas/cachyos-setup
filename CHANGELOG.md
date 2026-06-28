# Registro de cambios

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/)
y este proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [Unreleased]

### Changed
- describe idempotent changelog upsert contract

### Fixed
- esperar conectividad real antes de actualizar
- ensure byte-stable output on first vs subsequent runs
- preserve subsection headers for accumulated [Unreleased] entries
- make branch-scoped changelog update idempotent
- quote ExecStart paths to handle spaces in clone path
- resolve systemd unit script paths from clone location

