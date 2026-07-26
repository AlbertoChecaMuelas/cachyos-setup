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
  STATE_DIR="$STATE_DIR" OMARCHY_STATE_DIR="$OMARCHY_STATE_DIR" \
    CACHYOS_MODULES_DIR="${CACHYOS_MODULES_DIR:-}" \
    CACHYOS_INLINE=1 bash -c "echo | bash '$SCRIPT'"
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

@test "reboot re-evaluation: LAST_RUN_REBOOT_NEEDED=true but the running kernel's modules dir exists -> reboot no longer needed" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T09:30:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="true"
LAST_RUN_PACKAGE_COUNT="5"
EOF

  CACHYOS_MODULES_DIR="$BATS_TEST_TMPDIR/modules-installed"
  mkdir -p "$CACHYOS_MODULES_DIR"

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reinicio:  no necesario"* ]]
  [[ "$output" != *"RECOMENDADO"* ]]
}

@test "reboot re-evaluation: LAST_RUN_REBOOT_NEEDED=true and the running kernel's modules dir is gone -> reboot still recommended" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T09:35:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="true"
LAST_RUN_PACKAGE_COUNT="5"
EOF

  # Deliberately not created: simulates a running kernel that is no
  # longer installed (kernel/nvidia updated, reboot still pending).
  CACHYOS_MODULES_DIR="$BATS_TEST_TMPDIR/modules-not-installed"

  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reinicio:  RECOMENDADO (kernel/nvidia actualizados)"* ]]
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

@test "interactive [u] action takes the INLINE branch of update-now.sh, never the floating-terminal relaunch" {
  # journalctl/pkexec stubs so the real update-now.sh (invoked by the
  # [u] action) runs its inline flow with no real privilege
  # escalation — same stub pattern as tests/update-now.bats.
  local fake_bin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/journalctl" << 'EOF'
#!/usr/bin/env bash
echo "journal: fake live progress line"
while true; do sleep 0.05; done
EOF
  chmod +x "$fake_bin/journalctl"
  cat > "$fake_bin/pkexec" << 'EOF'
#!/usr/bin/env bash
sleep 0.1
exit 0
EOF
  chmod +x "$fake_bin/pkexec"

  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-17T11:00:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="2"
EOF

  # First "u" triggers the real update-now.sh inline; an empty line
  # then closes the visor on the second loop iteration.
  run env PATH="$fake_bin:$PATH" STATE_DIR="$STATE_DIR" OMARCHY_STATE_DIR="$OMARCHY_STATE_DIR" \
    CACHYOS_INLINE=1 \
    bash -c "printf 'u\n\n' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]

  [[ "$output" == *"Lanzando actualizacion manual..."* ]]
  # Proves the INLINE branch of update-now.sh actually ran here (its
  # journalctl/pkexec stubs executed and last-run.env was read and
  # shown) — the floating-terminal relaunch branch never produces
  # this output synchronously in the same process.
  [[ "$output" == *"journal: fake live progress line"* ]]
  [[ "$output" == *"Resultado: success"* ]]
  # The visor's loop kept running afterwards and re-rendered its own
  # state (the header appears once for the initial render, once more
  # for the re-render after the action).
  [ "$(grep -c '== Última actualización del sistema ==' <<< "$output")" -eq 2 ]
}

@test "interactive [u] action: a non-zero exit code from the invoked script does not break the loop" {
  # Isolated copy of show-last-run.sh alongside a stub update-now.sh
  # that simulates a failing invocation (rc=7). SCRIPTS_DIR/
  # UPDATE_NOW_SCRIPT are resolved relative to the script's own
  # location, so copying both files together lets us control the
  # invoked script's exit code without touching the real repo files.
  local copy_dir="$BATS_TEST_TMPDIR/scriptscopy"
  mkdir -p "$copy_dir"
  cp "$SCRIPT" "$copy_dir/show-last-run.sh"
  cat > "$copy_dir/update-now.sh" << 'EOF'
#!/usr/bin/env bash
echo "fake update-now.sh ran and is about to fail"
exit 7
EOF
  chmod +x "$copy_dir/update-now.sh"

  run env STATE_DIR="$STATE_DIR" OMARCHY_STATE_DIR="$OMARCHY_STATE_DIR" \
    CACHYOS_INLINE=1 \
    bash -c "printf 'u\n\n' | bash '$copy_dir/show-last-run.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake update-now.sh ran and is about to fail"* ]]
  # The non-zero rc (7) did not abort the loop: it re-rendered and
  # then exited cleanly on the following Enter.
  [ "$(grep -c '== Última actualización del sistema ==' <<< "$output")" -eq 2 ]
}
