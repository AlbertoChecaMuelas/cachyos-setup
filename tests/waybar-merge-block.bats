#!/usr/bin/env bats
# Tests for install.sh's waybar_merge_block() — comma-safety when
# inserting the cachyos-setup marker block as a new sibling of the last
# top-level member of config.jsonc, and idempotent re-run.
#
# Strategy: extract only the function body from install.sh (sed range
# between the literal "waybar_merge_block() {" line and the first "^}"
# at column 0) and source it, so we don't have to run the whole
# install.sh (which requires sudo / root paths at the top level).

INSTALL_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install.sh"

setup() {
  FUNC_FILE="$BATS_TEST_TMPDIR/waybar_merge_block.sh"
  sed -n '/^waybar_merge_block() {/,/^}/p' "$INSTALL_SH" > "$FUNC_FILE"
  [ -s "$FUNC_FILE" ]

  SNIPPET="$BATS_TEST_TMPDIR/snippet.jsonc"
  cat > "$SNIPPET" << 'EOF'
    "custom/cachyos-update": {
        "format": "{}"
    }
EOF

  CONFIG="$BATS_TEST_TMPDIR/config.jsonc"
  OPEN='// >>> cachyos-setup update module >>>'
  CLOSE='// <<< cachyos-setup update module <<<'
}

# Strips // line comments (best-effort, sufficient for our controlled
# fixtures) and validates the remainder is parseable JSON.
assert_valid_jsonc() {
  local file="$1"
  sed -E 's#[[:space:]]*//.*$##' "$file" | python3 -c "import json,sys; json.load(sys.stdin)"
}

merge() {
  bash -c "source '$FUNC_FILE'; waybar_merge_block '$SNIPPET' '$CONFIG' '$OPEN' '$CLOSE' '^}\$'"
}

@test "last top-level member is an object: block inserted, comma already correct, valid JSON" {
  cat > "$CONFIG" << 'EOF'
{
    "layer": "top",
    "custom/other": {
        "format": "x"
    }
}
EOF
  run merge
  [ "$status" -eq 0 ]
  grep -q 'custom/cachyos-update' "$CONFIG"
  # The pre-existing object closes with "}," so the sibling block follows correctly.
  grep -A1 '"custom/other"' "$CONFIG" | grep -q '"format": "x"'
  assert_valid_jsonc "$CONFIG"
}

@test "last top-level member is a scalar: comma is added and JSON stays valid" {
  cat > "$CONFIG" << 'EOF'
{
    "layer": "top",
    "height": 30
}
EOF
  run merge
  [ "$status" -eq 0 ]
  grep -q 'custom/cachyos-update' "$CONFIG"
  grep -q '"height": 30,$' "$CONFIG"
  assert_valid_jsonc "$CONFIG"
}

@test "last top-level member is a closed array: comma is added and JSON stays valid" {
  cat > "$CONFIG" << 'EOF'
{
    "height": 30,
    "modules-right": ["clock"]
}
EOF
  run merge
  [ "$status" -eq 0 ]
  grep -q 'custom/cachyos-update' "$CONFIG"
  grep -q '"modules-right": \["clock"\],$' "$CONFIG"
  assert_valid_jsonc "$CONFIG"
}

@test "last member with trailing inline comment: comma lands before the comment, comment stays intact" {
  cat > "$CONFIG" << 'EOF'
{
    "layer": "top",
    "height": 30 // px
}
EOF
  run merge
  [ "$status" -eq 0 ]
  # Comma must land right after the real content, before the comment.
  grep -q '"height": 30, // px$' "$CONFIG"
  # The comment text itself must survive unmutated (no "// px," or lost comment).
  ! grep -q '// px,' "$CONFIG"
  grep -q '// px' "$CONFIG"
  assert_valid_jsonc "$CONFIG"
}

@test "re-running with markers already present does not duplicate the block" {
  cat > "$CONFIG" << 'EOF'
{
    "layer": "top",
    "height": 30
}
EOF
  merge
  [ "$(grep -c -- "$OPEN" "$CONFIG")" -eq 1 ]

  # Second run: markers are now present, so waybar_merge_block must take
  # the replace-in-place path instead of inserting a second copy.
  run merge
  [ "$status" -eq 0 ]
  [ "$(grep -c -- "$OPEN" "$CONFIG")" -eq 1 ]
  [ "$(grep -c -- "$CLOSE" "$CONFIG")" -eq 1 ]
  [ "$(grep -c 'custom/cachyos-update' "$CONFIG")" -eq 1 ]
  assert_valid_jsonc "$CONFIG"
}
