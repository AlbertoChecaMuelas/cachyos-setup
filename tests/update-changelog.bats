#!/usr/bin/env bats
# Tests for tools/release/update-changelog.sh — idempotent upsert and filter logic
#
# Strategy: each test gets a fresh git repo via $BATS_TEST_TMPDIR with one base
# commit.  Test-specific commits are added as --allow-empty commits so no file
# tree is needed.  The script is invoked with --branch $BASE_SHA so that
# git log picks up only the commits added within that test.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/tools/release/update-changelog.sh"

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"

  # Base commit: minimal CHANGELOG with no [Unreleased] section.
  cat > "$REPO/CHANGELOG.md" << 'EOF'
# Changelog

## [0.1.0] - 2025-01-01
- Initial release
EOF
  git -C "$REPO" add CHANGELOG.md
  git -C "$REPO" commit -m "chore: init"

  # Capture the base SHA — used as the --branch argument so that git log
  # only returns commits added within each individual test.
  BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
}

# ---------------------------------------------------------------------------
# Test 1: docs(changelog): filter
# A commit whose subject starts with "docs(changelog):" must never produce
# a bullet in the changelog.  Without the filter it would be classified as
# "Changed" via the docs(*): case.
# ---------------------------------------------------------------------------
@test "commit with docs(changelog): prefix produces no bullet" {
  git -C "$REPO" commit --allow-empty \
    -m "docs(changelog): update [Unreleased] for upcoming PR"
  git -C "$REPO" commit --allow-empty -m "feat: add login page"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  [ "$status" -eq 0 ]

  # The feat bullet must appear.
  grep -q -- '- add login page' "$REPO/CHANGELOG.md"

  # No text from the docs(changelog) commit may appear as a bullet.
  ! grep -q -- 'update \[Unreleased\] for upcoming PR' "$REPO/CHANGELOG.md"
}

# ---------------------------------------------------------------------------
# Test 2: Dedup on upsert
# Running the script twice on the same branch must yield exactly one
# [Unreleased] header and zero duplicated bullets.
# ---------------------------------------------------------------------------
@test "running the script twice yields a single [Unreleased] header and no duplicate bullets" {
  git -C "$REPO" commit --allow-empty -m "feat: add dark mode"
  git -C "$REPO" commit --allow-empty -m "fix: resolve login crash"

  # First run: creates the [Unreleased] section from scratch.
  bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"

  # Second run: hits the idempotent-upsert path.
  run bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  [ "$status" -eq 0 ]

  # Exactly one [Unreleased] header.
  [ "$(grep -c '^## \[Unreleased\]' "$REPO/CHANGELOG.md")" -eq 1 ]

  # Each bullet appears exactly once.
  [ "$(grep -c -- '- add dark mode' "$REPO/CHANGELOG.md")" -eq 1 ]
  [ "$(grep -c -- '- resolve login crash' "$REPO/CHANGELOG.md")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Test 3: Accumulator
# A pre-existing "### Fixed" bullet that is NOT in the newly-computed block
# must survive under its original "### Fixed" header, and the canonical
# Added → Fixed ordering must be respected.
# ---------------------------------------------------------------------------
@test "pre-existing ### Fixed bullet survives under its header after re-run" {
  # Overwrite CHANGELOG.md with an [Unreleased] section that already contains
  # a Fixed bullet (simulates a prior run on a different set of commits).
  cat > "$REPO/CHANGELOG.md" << 'EOF'
# Changelog

## [Unreleased]

### Fixed
- prior-bug-fix

## [0.1.0] - 2025-01-01
- Initial release
EOF

  git -C "$REPO" commit --allow-empty -m "feat: new dashboard"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  [ "$status" -eq 0 ]

  # New Added bullet from the feat commit must appear.
  grep -q -- '- new dashboard' "$REPO/CHANGELOG.md"

  # The ### Fixed header and its prior bullet must survive.
  grep -q '^### Fixed' "$REPO/CHANGELOG.md"
  grep -q -- '- prior-bug-fix' "$REPO/CHANGELOG.md"

  # ### Added must precede ### Fixed (canonical section ordering).
  added_line="$(grep -n '^### Added' "$REPO/CHANGELOG.md" | head -1 | cut -d: -f1)"
  fixed_line="$(grep -n '^### Fixed' "$REPO/CHANGELOG.md" | head -1 | cut -d: -f1)"
  [ "$added_line" -lt "$fixed_line" ]
}

# ---------------------------------------------------------------------------
# Test 4: Idempotency
# Three consecutive runs on the same branch must produce byte-identical
# CHANGELOG.md output.
# ---------------------------------------------------------------------------
@test "output is byte-stable across three consecutive runs" {
  git -C "$REPO" commit --allow-empty -m "feat: export feature"
  git -C "$REPO" commit --allow-empty -m "fix: null pointer in parser"

  bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  snapshot1="$(cat "$REPO/CHANGELOG.md")"

  bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  snapshot2="$(cat "$REPO/CHANGELOG.md")"

  bash -c "cd '$REPO' && bash '$SCRIPT' --branch '$BASE_SHA'"
  snapshot3="$(cat "$REPO/CHANGELOG.md")"

  [ "$snapshot1" = "$snapshot2" ]
  [ "$snapshot2" = "$snapshot3" ]
}
