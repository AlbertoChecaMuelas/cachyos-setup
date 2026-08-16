#!/usr/bin/env bats
# Tests for scripts/update-system.sh's orphan pacman-lock guard and the
# "unable to lock database" vs network error classification (both added
# by .plans/pacman-orphan-lock.md).
#
# Strategy: extract each block by line-anchored sed range (same
# technique as write-last-run-record.bats) and run it in isolation with
# fake fuser/pgrep stubs on PATH and mock notify/write_summary/
# write_last_run_record shell functions, instead of running the whole
# script (which would perform real pacman/aur/notify-send calls).

UPDATE_SYSTEM_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/update-system.sh"

setup() {
  # Orphan-lock guard block: from the "if [[ -e "$PACMAN_LOCK" ]]; then"
  # line up to its matching top-level "fi". Deliberately excludes the
  # preceding "PACMAN_LOCK=/var/lib/pacman/db.lck" assignment line so
  # the test can inject its own (tmpdir) path via env instead of
  # touching the real system lock file.
  LOCK_GUARD_FILE="$BATS_TEST_TMPDIR/lock_guard.sh"
  sed -n '/^if \[\[ -e "\$PACMAN_LOCK" \]\]; then$/,/^fi$/p' "$UPDATE_SYSTEM_SH" > "$LOCK_GUARD_FILE"
  [ -s "$LOCK_GUARD_FILE" ]

  # Error-classification block: from "if [[ "$pacman_ok" -ne 1 ]]; then"
  # up to its matching top-level "fi" (the inner if/elif/else's own "fi"
  # is indented, so the anchored "^fi$" only matches the outer one).
  CLASSIFY_FILE="$BATS_TEST_TMPDIR/classify.sh"
  sed -n '/^if \[\[ "\$pacman_ok" -ne 1 \]\]; then$/,/^fi$/p' "$UPDATE_SYSTEM_SH" > "$CLASSIFY_FILE"
  [ -s "$CLASSIFY_FILE" ]

  STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR"
  LOG_FILE="$STATE_DIR/update.log"
  : > "$LOG_FILE"

  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"

  cat > "$FAKE_BIN/fuser" << 'EOF'
#!/usr/bin/env bash
exit "${FAKE_FUSER_RC:-1}"
EOF
  chmod +x "$FAKE_BIN/fuser"

  cat > "$FAKE_BIN/pgrep" << 'EOF'
#!/usr/bin/env bash
exit "${FAKE_PGREP_RC:-1}"
EOF
  chmod +x "$FAKE_BIN/pgrep"

  CALLS_FILE="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_FILE"
}

# $1=lock file path $2=fuser exit code $3=pgrep exit code
run_lock_guard() {
  PACMAN_LOCK="$1" \
    LOG_FILE="$LOG_FILE" \
    PATH="$FAKE_BIN:$PATH" \
    FAKE_FUSER_RC="$2" \
    FAKE_PGREP_RC="$3" \
    bash "$LOCK_GUARD_FILE"
}

# $1=content of the current run log (pacman failure output)
classify_failure() {
  local run_log="$BATS_TEST_TMPDIR/current-run.log"
  printf '%s\n' "$1" > "$run_log"
  : > "$CALLS_FILE"
  CURRENT_RUN_LOG="$run_log" \
    CLASSIFY_FILE="$CLASSIFY_FILE" \
    CALLS_FILE="$CALLS_FILE" \
    LOG_FILE="$LOG_FILE" \
    PACMAN_LOCK_FAIL_PATTERN='unable to lock database' \
    PACMAN_NETWORK_FAIL_PATTERN='Could not resolve host|failed to synchronize all databases|failed to retrieve some files|Temporary failure in name resolution' \
    PACMAN_MAX_ATTEMPTS=3 \
    bash -c '
notify() { echo "NOTIFY $*" >> "$CALLS_FILE"; }
write_summary() { echo "WRITE_SUMMARY $*" >> "$CALLS_FILE"; }
write_last_run_record() { echo "WRITE_LAST_RUN_RECORD $*" >> "$CALLS_FILE"; }
pacman_ok=0
source "$CLASSIFY_FILE"
'
}

@test "orphan lock guard: no lock file present is a no-op (nothing logged, guard does not error)" {
  local lock="$BATS_TEST_TMPDIR/db.lck"
  run run_lock_guard "$lock" 1 1
  [ "$status" -eq 0 ]
  [ ! -e "$lock" ]
  [ ! -s "$LOG_FILE" ]
}

@test "orphan lock guard: neither fuser nor pgrep -x pacman detect a live process -> lock is deleted and logged as huerfano" {
  local lock="$BATS_TEST_TMPDIR/db.lck"
  : > "$lock"

  run run_lock_guard "$lock" 1 1
  [ "$status" -eq 0 ]
  [ ! -e "$lock" ]
  grep -qF "lock huerfano de pacman detectado en $lock" "$LOG_FILE"
}

@test "orphan lock guard: fuser detects the lock file open -> lock is NOT deleted, logged as en uso" {
  local lock="$BATS_TEST_TMPDIR/db.lck"
  : > "$lock"

  run run_lock_guard "$lock" 0 1
  [ "$status" -eq 0 ]
  [ -e "$lock" ]
  grep -qF "en uso por un proceso vivo; no se toca" "$LOG_FILE"
}

@test "orphan lock guard: pgrep -x pacman detects a live process even though fuser sees nothing -> lock is NOT deleted (safety net)" {
  local lock="$BATS_TEST_TMPDIR/db.lck"
  : > "$lock"

  run run_lock_guard "$lock" 1 0
  [ "$status" -eq 0 ]
  [ -e "$lock" ]
  grep -qF "en uso por un proceso vivo; no se toca" "$LOG_FILE"
}

@test "error classification: log matching PACMAN_LOCK_FAIL_PATTERN is classified as db locked, not as network" {
  run classify_failure 'error: failed to synchronize all databases (unable to lock database)'
  [ "$status" -eq 1 ]
  grep -qF "base de datos bloqueada" "$CALLS_FILE"
  ! grep -qF "Error de red" "$CALLS_FILE"
  grep -qF 'WRITE_LAST_RUN_RECORD failure pacman -Syu fallo (base de datos bloqueada) false 0' "$CALLS_FILE"
}

@test "error classification: log matching only PACMAN_NETWORK_FAIL_PATTERN still classifies as network (no regression)" {
  run classify_failure 'error: Could not resolve host archlinux.org'
  [ "$status" -eq 1 ]
  grep -qF "Error de red al actualizar" "$CALLS_FILE"
  ! grep -qF "base de datos bloqueada" "$CALLS_FILE"
  grep -qF 'WRITE_LAST_RUN_RECORD failure pacman -Syu fallo (red/DNS) false 0' "$CALLS_FILE"
}

@test "error classification: log matching neither pattern falls back to the generic pacman error" {
  run classify_failure 'error: some unrelated pacman failure'
  [ "$status" -eq 1 ]
  ! grep -qF "base de datos bloqueada" "$CALLS_FILE"
  ! grep -qF "Error de red" "$CALLS_FILE"
  grep -qF 'WRITE_LAST_RUN_RECORD failure pacman -Syu fallo false 0' "$CALLS_FILE"
}
