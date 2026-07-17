#!/usr/bin/env bats
# Tests for scripts/show-last-run.sh — differentiated display of the
# three possible LAST_RUN_RESULT states, including the failure reason
# for "partial" and "failed"; plus the newer omarchy-on-cachyos
# section (read of OMARCHY_STATE_DIR/omarchy-check.env) and its
# interactive "[c]" action that re-runs check-omarchy-update.sh.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/show-last-run.sh"

setup() {
  STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR"
  # Isolated from the real machine's $HOME/.local/state/cachyos-setup,
  # which may hold a real omarchy-check.env from actual usage.
  OMARCHY_STATE_DIR="$BATS_TEST_TMPDIR/omarchy-state"
  mkdir -p "$OMARCHY_STATE_DIR"

  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
}

# $1=dir $2=tag (empty = no tag created) — same helper pattern as
# tests/check-omarchy-update.bats, used only by the "[c]" integration
# test below.
make_repo() {
  local dir="$1" tag="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" commit -q --allow-empty -m "init"
  if [[ -n "$tag" ]]; then
    git -C "$dir" tag "$tag"
  fi
}

run_show() {
  STATE_DIR="$STATE_DIR" OMARCHY_STATE_DIR="$OMARCHY_STATE_DIR" CACHYOS_INLINE=1 bash -c "echo | bash '$SCRIPT'"
}

@test "no record yet: informs the user without erroring" {
  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"No hay ningún registro de actualización todavía."* ]]
}

@test "success result is shown without a Motivo line" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T09:00:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="4"
EOF

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resultado: success"* ]]
  [[ "$output" != *"Motivo:"* ]]
}

@test "partial result is shown differentiated from failure, with its Motivo" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T09:10:00"
LAST_RUN_RESULT="partial"
LAST_RUN_FAIL_REASON="AUR no actualizado (ver log)"
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="3"
EOF

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resultado: partial"* ]]
  [[ "$output" == *"pacman OK, AUR falló"* ]]
  [[ "$output" == *"Motivo:    AUR no actualizado (ver log)"* ]]
}

@test "failure result is shown differentiated from partial, with its Motivo" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T09:20:00"
LAST_RUN_RESULT="failure"
LAST_RUN_FAIL_REASON="pacman -Syu fallo"
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="0"
EOF

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resultado: failure"* ]]
  [[ "$output" == *"Motivo:    pacman -Syu fallo"* ]]
  # Must not be confused with the partial-specific wording.
  [[ "$output" != *"pacman OK, AUR falló"* ]]
}

@test "omarchy section: no state file yet informs it hasn't been checked" {
  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"== Comprobación de omarchy-on-cachyos =="* ]]
  [[ "$output" == *"Estado:    aún no comprobado"* ]]
  [[ "$output" == *"Pendiente: —"* ]]
}

@test "omarchy section: renders local/remote versions and pending=SI from the state file" {
  cat > "$OMARCHY_STATE_DIR/omarchy-check.env" << 'EOF'
OMARCHY_CHECK_TIMESTAMP="2026-07-17T09:00:00+02:00"
OMARCHY_LOCAL_VERSION="v1.0.0"
OMARCHY_REMOTE_VERSION="v2.0.0"
OMARCHY_UPDATE_AVAILABLE="true"
EOF

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Local:     v1.0.0"* ]]
  [[ "$output" == *"Remota:    v2.0.0"* ]]
  [[ "$output" == *"Pendiente: SÍ (actualización disponible)"* ]]
}

@test "omarchy section: renders pending=no when the state file says no update is available" {
  cat > "$OMARCHY_STATE_DIR/omarchy-check.env" << 'EOF'
OMARCHY_CHECK_TIMESTAMP="2026-07-17T09:00:00+02:00"
OMARCHY_LOCAL_VERSION="v1.0.0"
OMARCHY_REMOTE_VERSION="v1.0.0"
OMARCHY_UPDATE_AVAILABLE="false"
EOF

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pendiente: no"* ]]
  [[ "$output" != *"Pendiente: SÍ"* ]]
}

@test "interactive [c] action re-runs check-omarchy-update.sh and re-renders the omarchy section live" {
  local local_dir="$BATS_TEST_TMPDIR/omarchy-local"
  local remote_dir="$BATS_TEST_TMPDIR/omarchy-remote"
  make_repo "$local_dir" "v1.0.0"
  make_repo "$remote_dir" "v2.0.0"

  # First "c" triggers the real check-omarchy-update.sh (its own env
  # vars are inherited from this same process, no stub needed), then
  # an empty line closes the window on the second loop iteration.
  run env STATE_DIR="$STATE_DIR" OMARCHY_STATE_DIR="$OMARCHY_STATE_DIR" \
    OMARCHY_DIR="$local_dir" OMARCHY_URL="$remote_dir" \
    CACHYOS_INLINE=1 \
    bash -c "printf 'c\n\n' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]

  # Before the check: the state file did not exist yet.
  [[ "$output" == *"Estado:    aún no comprobado"* ]]
  [[ "$output" == *"Comprobando omarchy..."* ]]
  # After the check: the re-render shows the freshly written state.
  [[ "$output" == *"Local:     v1.0.0"* ]]
  [[ "$output" == *"Remota:    v2.0.0"* ]]
  [[ "$output" == *"Pendiente: SÍ (actualización disponible)"* ]]

  [ -f "$OMARCHY_STATE_DIR/omarchy-check.env" ]
}
