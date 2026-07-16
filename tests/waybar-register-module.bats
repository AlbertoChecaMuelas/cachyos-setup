#!/usr/bin/env bats
# Tests for install.sh's waybar_register_module() — registering
# "custom/cachyos-update" inside the modules-right array, both for
# single-line and multi-line array layouts, and the graceful degrade
# (warn, don't touch the file) only when the "modules-right" key
# can't be located at all.

INSTALL_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install.sh"

setup() {
  FUNC_FILE="$BATS_TEST_TMPDIR/waybar_register_module.sh"
  sed -n '/^waybar_register_module() {/,/^}/p' "$INSTALL_SH" > "$FUNC_FILE"
  [ -s "$FUNC_FILE" ]

  CONFIG="$BATS_TEST_TMPDIR/config.jsonc"
}

# Strips // line comments (best-effort, sufficient for our controlled
# fixtures) and validates the remainder is parseable JSON. Mirrors the
# helper in waybar-merge-block.bats.
assert_valid_jsonc() {
  local file="$1"
  sed -E 's#[[:space:]]*//.*$##' "$file" | python3 -c "import json,sys; json.load(sys.stdin)"
}

register() {
  bash -c "source '$FUNC_FILE'; waybar_register_module '$CONFIG' 'custom/cachyos-update'"
}

@test "single-line modules-right: module gets registered inside the array" {
  cat > "$CONFIG" << 'EOF'
{
    "layer": "top",
    "modules-right": ["clock", "battery"]
}
EOF
  run register
  [ "$status" -eq 0 ]
  grep '"modules-right"' "$CONFIG" | grep -qF '"custom/cachyos-update"'
  # Original entries survive.
  grep '"modules-right"' "$CONFIG" | grep -qF '"clock"'
  grep '"modules-right"' "$CONFIG" | grep -qF '"battery"'
}

@test "single-line modules-right: re-running is idempotent (no duplicate entry)" {
  cat > "$CONFIG" << 'EOF'
{
    "modules-right": ["clock"]
}
EOF
  register
  run register
  [ "$status" -eq 0 ]
  local count
  count="$(grep -o 'custom/cachyos-update' "$CONFIG" | wc -l)"
  [ "$count" -eq 1 ]
}

@test "multi-line modules-right: module gets inserted into the array and the file stays valid JSONC" {
  cat > "$CONFIG" << 'EOF'
{
    "modules-right": [
        "clock",
        "battery"
    ]
}
EOF
  run register
  [ "$status" -eq 0 ]
  assert_valid_jsonc "$CONFIG"
  # New module registered, right before the closing bracket.
  grep -qF '"custom/cachyos-update"' "$CONFIG"
  # Original entries survive with a trailing comma added to the
  # previously-last entry so the array stays valid.
  grep -qF '"clock",' "$CONFIG"
  grep -qF '"battery",' "$CONFIG"
}
