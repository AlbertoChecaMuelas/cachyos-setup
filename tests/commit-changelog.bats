#!/usr/bin/env bats
# Tests for tools/release/commit-changelog.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/tools/release/commit-changelog.sh"

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"
  # Initial commit so HEAD is valid for any subsequent git operations
  echo "# readme" > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -m "chore: init"
}

@test "exit 3 cuando CHANGELOG.md no tiene cambios staged" {
  # CHANGELOG.md already committed with no modifications:
  # git add is a no-op, diff --cached is empty → script exits 3
  echo "# Changelog" > "$REPO/CHANGELOG.md"
  git -C "$REPO" add CHANGELOG.md
  git -C "$REPO" commit -m "docs: add changelog"

  run bash -c "cd '$REPO' && bash '$SCRIPT'"
  [ "$status" -eq 3 ]
}

@test "exit 0 y crea commit cuando CHANGELOG.md tiene cambios" {
  # CHANGELOG.md with new content, not yet staged:
  # git add stages it, diff --cached shows changes → script commits → exit 0
  echo "## [Unreleased]" > "$REPO/CHANGELOG.md"

  run bash -c "cd '$REPO' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  last_msg="$(git -C "$REPO" log -1 --format='%s')"
  [ "$last_msg" = "docs(changelog): update [Unreleased] for upcoming PR" ]
}
