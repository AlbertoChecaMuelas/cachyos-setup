#!/usr/bin/env bats
# Tests for scripts/update-system.sh's write_last_run_record() — atomic
# write of the durable last-run record and correct LAST_RUN_RESULT
# per scenario.
#
# Strategy: extract only the function body (sed range between the
# literal "write_last_run_record() {" line and the first "^}" at
# column 0) and source it, so we don't have to run the whole
# update-system.sh (which performs real pacman/aur/notify-send calls
# at the top level).

UPDATE_SYSTEM_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/update-system.sh"

setup() {
  FUNC_FILE="$BATS_TEST_TMPDIR/write_last_run_record.sh"
  sed -n '/^write_last_run_record() {/,/^}/p' "$UPDATE_SYSTEM_SH" > "$FUNC_FILE"
  [ -s "$FUNC_FILE" ]

  STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR"
}

write_record() {
  # $1=result $2=fail_reason $3=reboot_needed $4=pkg_count $5=pkg_list_file
  STATE_DIR="$STATE_DIR" bash -c "source '$FUNC_FILE'; write_last_run_record \"\$@\"" _ "$@"
}

@test "atomic write: no orphan .tmp.* files remain in STATE_DIR after a run" {
  local pkgs="$BATS_TEST_TMPDIR/pkgs.txt"
  printf 'linux\nmesa\n' > "$pkgs"

  run write_record "success" "" "false" "2" "$pkgs"
  [ "$status" -eq 0 ]

  [ -f "$STATE_DIR/last-run.env" ]
  [ -f "$STATE_DIR/last-run-packages.txt" ]
  # No leftover temp files of either kind (the real names are dotfiles,
  # e.g. ".last-run.env.tmp.<pid>", so dotglob is required to see them).
  run find "$STATE_DIR" -maxdepth 1 -name '*.tmp.*'
  [ -z "$output" ]
}

@test "atomic write: no orphan .tmp.* files remain even without a package list file" {
  run write_record "failure" "pacman -Syu fallo" "false" "0" ""
  [ "$status" -eq 0 ]

  [ -f "$STATE_DIR/last-run.env" ]
  [ -f "$STATE_DIR/last-run-packages.txt" ]
  run find "$STATE_DIR" -maxdepth 1 -name '*.tmp.*'
  [ -z "$output" ]
}

@test "scenario success: pacman and AUR both OK is recorded as LAST_RUN_RESULT=success" {
  local pkgs="$BATS_TEST_TMPDIR/pkgs.txt"
  printf 'linux\n' > "$pkgs"

  write_record "success" "" "true" "1" "$pkgs"

  source "$STATE_DIR/last-run.env"
  [ "$LAST_RUN_RESULT" = "success" ]
  [ "$LAST_RUN_FAIL_REASON" = "" ]
  [ "$LAST_RUN_REBOOT_NEEDED" = "true" ]
  [ "$LAST_RUN_PACKAGE_COUNT" = "1" ]
  grep -qF 'linux' "$STATE_DIR/last-run-packages.txt"
}

@test "scenario partial: pacman OK but AUR fails is recorded as LAST_RUN_RESULT=partial with the AUR reason" {
  local pkgs="$BATS_TEST_TMPDIR/pkgs.txt"
  printf 'mesa\n' > "$pkgs"

  write_record "partial" "AUR no actualizado (ver /var/log/x)" "false" "1" "$pkgs"

  source "$STATE_DIR/last-run.env"
  [ "$LAST_RUN_RESULT" = "partial" ]
  [ "$LAST_RUN_FAIL_REASON" = "AUR no actualizado (ver /var/log/x)" ]
}

@test "scenario failure: pacman fails is recorded as LAST_RUN_RESULT=failure with an empty package list" {
  write_record "failure" "pacman -Syu fallo" "false" "0" ""

  source "$STATE_DIR/last-run.env"
  [ "$LAST_RUN_RESULT" = "failure" ]
  [ "$LAST_RUN_FAIL_REASON" = "pacman -Syu fallo" ]
  [ "$LAST_RUN_PACKAGE_COUNT" = "0" ]
  [ ! -s "$STATE_DIR/last-run-packages.txt" ]
}
