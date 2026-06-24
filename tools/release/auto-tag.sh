#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

semver_ok() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

LATEST_TAG="$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"

if [[ -n "${MANUAL_VERSION:-}" ]]; then
  VERSION="${MANUAL_VERSION#v}"
  if ! semver_ok "${VERSION}"; then
    echo "auto-tag: MANUAL_VERSION='${MANUAL_VERSION}' is not valid semver" >&2
    exit 2
  fi
else
  if [[ -z "${LATEST_TAG}" ]]; then
    VERSION="1.0.0"
  else
    BASE="${LATEST_TAG#v}"
    RANGE="${LATEST_TAG}..HEAD"
    LOG="$(git log --format='%B' "${RANGE}")"
    BUMP="none"
    if grep -qE '(^|\n)BREAKING CHANGE|(^|\n)[a-z]+(\([^)]*\))?!:' <<<"${LOG}"; then
      BUMP="major"
    elif grep -qE '(^|\n)feat(\([^)]*\))?:' <<<"${LOG}"; then
      BUMP="minor"
    elif grep -qE '(^|\n)fix(\([^)]*\))?:' <<<"${LOG}"; then
      BUMP="patch"
    fi
    if [[ "${BUMP}" == "none" ]]; then
      echo "auto-tag: no feat/fix/breaking commits since ${LATEST_TAG}; no release"
      exit 0
    fi
    IFS='.' read -r MAJ MIN PAT <<<"${BASE}"
    case "${BUMP}" in
      major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
      minor) MIN=$((MIN+1)); PAT=0 ;;
      patch) PAT=$((PAT+1)) ;;
    esac
    VERSION="${MAJ}.${MIN}.${PAT}"
  fi
fi

TAG="v${VERSION}"
echo "auto-tag: target tag ${TAG}"

if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
  echo "auto-tag: tag ${TAG} already exists locally; nothing to do"
  exit 0
fi
if git ls-remote --tags --exit-code origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "auto-tag: tag ${TAG} already exists on origin; nothing to do"
  exit 0
fi

CURRENT_SHA="$(git rev-parse HEAD)"
git config --local user.email "ci-bot@cachyos-setup"
git config --local user.name "cachyos-ci-bot"

if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi

git tag -a "${TAG}" -m "Release ${TAG}" "${CURRENT_SHA}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "auto-tag: --dry-run set; skipping push"
  exit 0
fi

if ! git push origin "refs/tags/${TAG}"; then
  echo "auto-tag: git push failed" >&2
  exit 4
fi
echo "auto-tag: pushed ${TAG}"
