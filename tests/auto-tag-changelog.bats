#!/usr/bin/env bats
# Tests for the [Unreleased] close block in tools/release/auto-tag.sh
#
# Strategy: run auto-tag.sh against a real git repo with MANUAL_VERSION=1.0.0
# to skip version detection, and a git mock that intercepts ls-remote (exit 1,
# tag not on remote) and push (exit 0, simulating successful push) so the full
# changelog-close block executes without requiring a real remote.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/tools/release/auto-tag.sh"

setup() {
  REAL_GIT="$(command -v git)"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"
  # At least one commit so git rev-parse HEAD succeeds
  echo "# readme" > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -m "chore: init"

  # Build a mock git that:
  #   ls-remote → exit 1  (tag does not exist on remote; script continues)
  #   push      → exit 0  (simulates successful push; script continues to changelog block)
  #   *         → exec real git (all other operations are real)
  MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  {
    echo '#!/usr/bin/env bash'
    echo "REAL_GIT=\"$REAL_GIT\""
    cat << 'ENDMOCK'
# Skip leading -C <dir> pairs to identify the actual subcommand
args=("$@")
i=0
while [[ $i -lt ${#args[@]} && "${args[$i]}" == "-C" ]]; do
  i=$((i+2))
done
cmd="${args[$i]:-}"
case "$cmd" in
  ls-remote) exit 1 ;;
  push)      exit 0 ;;
  *)         exec "$REAL_GIT" "$@" ;;
esac
ENDMOCK
  } > "$MOCK_BIN/git"
  chmod +x "$MOCK_BIN/git"
  export PATH="$MOCK_BIN:$PATH"
}

@test "dry-run no modifica CHANGELOG.md" {
  local original="# Changelog -- dry-run sentinel"
  echo "$original" > "$REPO/CHANGELOG.md"

  # --dry-run causes auto-tag.sh to exit 0 before the changelog block
  run bash -c "cd '$REPO' && MANUAL_VERSION=1.0.0 bash '$SCRIPT' --dry-run"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/CHANGELOG.md")" = "$original" ]
}

@test "[Unreleased] vacío se salta sin modificar CHANGELOG.md" {
  cat > "$REPO/CHANGELOG.md" << 'EOF'
# Changelog

## [Unreleased]

## [0.9.0] - 2024-01-01
- Old release notes
EOF
  local before
  before="$(cat "$REPO/CHANGELOG.md")"

  run bash -c "cd '$REPO' && MANUAL_VERSION=1.0.0 bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/CHANGELOG.md")" = "$before" ]
}

@test "[Unreleased] con contenido se cierra con la nueva versión" {
  cat > "$REPO/CHANGELOG.md" << 'EOF'
# Changelog

## [Unreleased]
- feat: something new

## [0.9.0] - 2024-01-01
- Old release notes
EOF

  run bash -c "cd '$REPO' && MANUAL_VERSION=1.0.0 bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  # New versioned section must appear in the file
  grep -q '\[1\.0\.0\]' "$REPO/CHANGELOG.md"
  # [Unreleased] header must still be present (left empty for future entries)
  grep -q '## \[Unreleased\]' "$REPO/CHANGELOG.md"
}
