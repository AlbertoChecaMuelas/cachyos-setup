#!/usr/bin/env bats
# Tests for scripts/check-omarchy-update.sh — persistence of the
# durable sourceable state file (omarchy-check.env) with its 4
# contract keys (OMARCHY_CHECK_TIMESTAMP, OMARCHY_LOCAL_VERSION,
# OMARCHY_REMOTE_VERSION, OMARCHY_UPDATE_AVAILABLE), across the 3
# branches: normal success (version comparison), OMARCHY_DIR missing,
# and unreadable upstream.
#
# Strategy: run the real script end-to-end against real local git
# repos created on the fly in BATS_TEST_TMPDIR (both the "local"
# clone and the "remote", the latter addressed by its local path,
# which `git ls-remote` supports natively). No network access, no
# mocking of git itself — only the repos it operates on are faked.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-omarchy-update.sh"

setup() {
  STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR"

  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
}

# $1=dir $2=tag (empty = no tag created)
make_repo() {
  local dir="$1" tag="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" commit -q --allow-empty -m "init"
  if [[ -n "$tag" ]]; then
    git -C "$dir" tag "$tag"
  fi
}

run_check() {
  # $1=OMARCHY_DIR $2=OMARCHY_URL
  OMARCHY_DIR="$1" OMARCHY_URL="$2" OMARCHY_STATE_DIR="$STATE_DIR" bash "$SCRIPT"
}

@test "same local and remote version: persists the 4 keys and marks no update pending" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$local_dir" "v1.0.0"
  make_repo "$remote_dir" "v1.0.0"

  run run_check "$local_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  source "$STATE_DIR/omarchy-check.env"
  [ -n "$OMARCHY_CHECK_TIMESTAMP" ]
  [ "$OMARCHY_LOCAL_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_REMOTE_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "false" ]
}

@test "remote version newer than local: marks an update pending" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$local_dir" "v1.0.0"
  make_repo "$remote_dir" "v2.0.0"

  run run_check "$local_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  source "$STATE_DIR/omarchy-check.env"
  [ "$OMARCHY_LOCAL_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_REMOTE_VERSION" = "v2.0.0" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "true" ]
}

@test "empty local version (no local tag): treated as an update pending" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$local_dir" ""
  make_repo "$remote_dir" "v1.0.0"

  run run_check "$local_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  source "$STATE_DIR/omarchy-check.env"
  [ "$OMARCHY_LOCAL_VERSION" = "" ]
  [ "$OMARCHY_REMOTE_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "true" ]
}

@test "local version newer than remote (downgrade): does not mark an update pending" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$local_dir" "v2.0.0"
  make_repo "$remote_dir" "v1.0.0"

  run run_check "$local_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  source "$STATE_DIR/omarchy-check.env"
  [ "$OMARCHY_LOCAL_VERSION" = "v2.0.0" ]
  [ "$OMARCHY_REMOTE_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "false" ]
}

@test "edge case: OMARCHY_DIR does not exist yet — still persists the 4 keys with edge defaults" {
  local missing_dir="$BATS_TEST_TMPDIR/does-not-exist"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$remote_dir" "v1.0.0"

  run run_check "$missing_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  [ -f "$STATE_DIR/omarchy-check.env" ]
  source "$STATE_DIR/omarchy-check.env"
  [ -n "$OMARCHY_CHECK_TIMESTAMP" ]
  [ "$OMARCHY_LOCAL_VERSION" = "" ]
  [ "$OMARCHY_REMOTE_VERSION" = "" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "false" ]
}

@test "edge case: unreadable upstream — still persists the 4 keys, local version preserved, remote empty" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local unreadable_url="$BATS_TEST_TMPDIR/no-such-remote"
  make_repo "$local_dir" "v1.0.0"

  run run_check "$local_dir" "$unreadable_url"
  [ "$status" -eq 0 ]

  [ -f "$STATE_DIR/omarchy-check.env" ]
  source "$STATE_DIR/omarchy-check.env"
  [ -n "$OMARCHY_CHECK_TIMESTAMP" ]
  [ "$OMARCHY_LOCAL_VERSION" = "v1.0.0" ]
  [ "$OMARCHY_REMOTE_VERSION" = "" ]
  [ "$OMARCHY_UPDATE_AVAILABLE" = "false" ]
}

@test "atomic write: no orphan .tmp.* files remain in OMARCHY_STATE_DIR after a run" {
  local local_dir="$BATS_TEST_TMPDIR/local"
  local remote_dir="$BATS_TEST_TMPDIR/remote"
  make_repo "$local_dir" "v1.0.0"
  make_repo "$remote_dir" "v1.0.0"

  run run_check "$local_dir" "$remote_dir"
  [ "$status" -eq 0 ]

  run find "$STATE_DIR" -maxdepth 1 -name '.omarchy-check.env.tmp.*'
  [ -z "$output" ]
}

@test "regression: default OMARCHY_URL (env var unset) points to the current fork, not the old upstream" {
  # No ejecuta el script completo (evitaria una llamada real de red vía
  # git ls-remote): extrae y evalua solo la linea de asignacion por
  # defecto de OMARCHY_URL para fijar el valor esperado tras el fix del
  # remoto por defecto (mroboff -> AlbertoChecaMuelas).
  run bash -c '
    unset OMARCHY_URL
    eval "$(grep -m1 "^OMARCHY_URL=" "'"$SCRIPT"'")"
    echo "$OMARCHY_URL"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/AlbertoChecaMuelas/omarchy-on-cachyos.git" ]
}
