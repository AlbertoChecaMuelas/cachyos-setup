#!/usr/bin/env bash
# Stagea CHANGELOG.md y commitea; exit 3 si no hay cambios que stagear.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
git -C "$ROOT" add CHANGELOG.md
if git -C "$ROOT" diff --cached --quiet -- CHANGELOG.md; then
  echo "commit-changelog: nada que commitear (CHANGELOG.md sin cambios)"
  exit 3
fi
git -C "$ROOT" commit -m "docs(changelog): update [Unreleased] for upcoming PR" -- CHANGELOG.md
echo "commit-changelog: commit creado"
