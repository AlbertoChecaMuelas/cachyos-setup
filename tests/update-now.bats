#!/usr/bin/env bats
# Tests for scripts/update-now.sh — live journalctl progress, no
# orphan background process, no silent abort on pkexec failure, and
# "Motivo:" shown for both failure and partial.
#
# Strategy: run the script's CACHYOS_INLINE=1 code path (bypasses the
# floating-terminal relaunch) with fake pkexec/journalctl stubs on
# PATH, so no real privilege escalation happens. journalctl's stub
# writes its own PID to a file so the test can assert it is no longer
# running once the script returns (proves kill+wait actually reaped
# it, no orphaned "journalctl -f").

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/update-now.sh"

setup() {
  STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR"

  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"

  JOURNAL_PID_FILE="$BATS_TEST_TMPDIR/journal.pid"

  # journalctl -f stub: proves it is invoked (marker line reaches
  # stdout, i.e. is NOT redirected to /dev/null) and stays alive in the
  # background until killed, like the real `-f` follow mode would.
  cat > "$FAKE_BIN/journalctl" << 'EOF'
#!/usr/bin/env bash
echo $$ > "$JOURNAL_PID_FILE"
echo "journal: fake live progress line"
while true; do sleep 0.05; done
EOF
  chmod +x "$FAKE_BIN/journalctl"

  # pkexec stub: simulates `pkexec systemctl start <service>` blocking
  # for a bit (like the real oneshot unit would) then returning the
  # exit code requested via PKEXEC_EXIT_CODE.
  cat > "$FAKE_BIN/pkexec" << 'EOF'
#!/usr/bin/env bash
sleep 0.2
exit "${PKEXEC_EXIT_CODE:-0}"
EOF
  chmod +x "$FAKE_BIN/pkexec"
}

run_update_now() {
  # $1=pkexec exit code
  PATH="$FAKE_BIN:$PATH" \
    STATE_DIR="$STATE_DIR" \
    JOURNAL_PID_FILE="$JOURNAL_PID_FILE" \
    PKEXEC_EXIT_CODE="$1" \
    CACHYOS_INLINE=1 \
    bash -c "echo | bash '$SCRIPT'"
}

@test "journalctl output reaches stdout and the process is reaped after pkexec succeeds" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T10:00:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="3"
EOF

  run run_update_now 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"journal: fake live progress line"* ]]
  [[ "$output" == *"Resultado: success"* ]]

  [ -f "$JOURNAL_PID_FILE" ]
  journal_pid="$(cat "$JOURNAL_PID_FILE")"
  ! kill -0 "$journal_pid" 2>/dev/null
}

@test "pkexec failure does not abort the script: last-run.env is still read and shown, journalctl still reaped" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T10:05:00"
LAST_RUN_RESULT="failure"
LAST_RUN_FAIL_REASON="pacman -Syu fallo"
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="0"
EOF

  run run_update_now 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"devolvio codigo de salida 1"* ]]
  [[ "$output" == *"Resultado: failure"* ]]
  [[ "$output" == *"Motivo:    pacman -Syu fallo"* ]]

  journal_pid="$(cat "$JOURNAL_PID_FILE")"
  ! kill -0 "$journal_pid" 2>/dev/null
}

@test "\"Motivo:\" line is shown for a partial result, not only for failure" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-15T10:10:00"
LAST_RUN_RESULT="partial"
LAST_RUN_FAIL_REASON="AUR no actualizado (ver log)"
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="2"
EOF

  run run_update_now 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resultado: partial"* ]]
  [[ "$output" == *"Motivo:    AUR no actualizado (ver log)"* ]]
}

@test "CACHYOS_SKIP_PAUSE=1 skips the final pause: exits 0 even with stdin closed" {
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-17T11:00:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="1"
EOF

  run env PATH="$FAKE_BIN:$PATH" STATE_DIR="$STATE_DIR" JOURNAL_PID_FILE="$JOURNAL_PID_FILE" \
    PKEXEC_EXIT_CODE=0 CACHYOS_INLINE=1 CACHYOS_SKIP_PAUSE=1 \
    bash -c "bash '$SCRIPT' </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Pulsa Enter"* ]]
  [[ "$output" == *"Resultado: success"* ]]
}

@test "without CACHYOS_SKIP_PAUSE (unset), the final pause still runs exactly as before" {
  # bash's `read -p` prompt is only ever displayed on a real terminal
  # (never under bats' piped stdin), so we cannot assert on the
  # prompt text itself. Instead we prove the read genuinely executes:
  # with stdin fully closed, an un-guarded `read` at EOF returns
  # non-zero and, under `set -e`, aborts the script — the exact
  # opposite of the CACHYOS_SKIP_PAUSE=1 case above, which exits 0
  # under the very same closed-stdin condition.
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-17T11:05:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="1"
EOF

  run env PATH="$FAKE_BIN:$PATH" STATE_DIR="$STATE_DIR" JOURNAL_PID_FILE="$JOURNAL_PID_FILE" \
    PKEXEC_EXIT_CODE=0 CACHYOS_INLINE=1 \
    bash -c "bash '$SCRIPT' </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Resultado: success"* ]]
}

@test "CACHYOS_SKIP_PAUSE=0 behaves the same as unset: the pause still runs" {
  # Same reasoning as the "unset" case above: closed stdin makes the
  # un-guarded final read fail and abort the script under set -e,
  # proving the pause is actually reached when the guard is =0.
  cat > "$STATE_DIR/last-run.env" << 'EOF'
LAST_RUN_TIMESTAMP="2026-07-17T11:06:00"
LAST_RUN_RESULT="success"
LAST_RUN_FAIL_REASON=""
LAST_RUN_REBOOT_NEEDED="false"
LAST_RUN_PACKAGE_COUNT="1"
EOF

  run env PATH="$FAKE_BIN:$PATH" STATE_DIR="$STATE_DIR" JOURNAL_PID_FILE="$JOURNAL_PID_FILE" \
    PKEXEC_EXIT_CODE=0 CACHYOS_INLINE=1 CACHYOS_SKIP_PAUSE=0 \
    bash -c "bash '$SCRIPT' </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Resultado: success"* ]]
}
