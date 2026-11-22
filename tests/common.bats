#!/usr/bin/env bats
# lib/common.sh and lib/output.sh: config parsing, JSON, prompts, records.

load helpers

setup() {
  beast_setup
  BEAST_ROOT=$REPO_ROOT
  # shellcheck source=../lib/output.sh
  . "$REPO_ROOT/lib/output.sh"
  # shellcheck source=../lib/common.sh
  . "$REPO_ROOT/lib/common.sh"
  BEAST_RUN_DIR="$TMP/run"
  mkdir -p "$BEAST_RUN_DIR"
}
teardown() { beast_teardown; }

@test "json_str escapes quotes, backslashes and control characters" {
  run json_str $'a "b" \\ c\nd\te\001'
  [ "$output" = '"a \"b\" \\ c\nd\te"' ]
  printf '%s' "$output" | python3 -c 'import json,sys; json.loads(sys.stdin.read())'
}

@test "json_arr builds an array of strings" {
  run json_arr one 'two "2"'
  [ "$output" = '["one","two \"2\""]' ]
  run json_arr
  [ "$output" = '[]' ]
}

@test "the defaults come from config/beast.conf.example" {
  load_config
  [ "$HOST_NAME" = beast ]
  [ "$LIGHTS_RAM_DEVICES" = "ENE DRAM" ]
  [ "$LIGHTS_MB_ZONES" = "0 1 2 3" ]
  [ "$RAM_MAX_MTS" = 5600 ]
  [ "$WIFI_CONNECTION" = "" ]
  [ "$BEAST_CONFIG" = "$HOME/.config/beast/beast.conf" ]
}

@test "the user config overrides defaults; quotes and comments are handled" {
  mkdir -p "$HOME/.config/beast"
  cat >"$HOME/.config/beast/beast.conf" <<'CONF'
# comment
LIGHTS_BOOT=hardware   # keep the rainbow
WIFI_CONNECTION="My Net # 5G"
LIGHTS_ON_COLOR='00AAFF'
  RAM_EXPECTED_STICKS=1
CONF
  load_config
  [ "$LIGHTS_BOOT" = hardware ]
  [ "$WIFI_CONNECTION" = "My Net # 5G" ]
  [ "$LIGHTS_ON_COLOR" = 00AAFF ]
  [ "$RAM_EXPECTED_STICKS" = 1 ]
}

@test "the config is parsed, not executed, and unknown keys are ignored" {
  mkdir -p "$HOME/.config/beast"
  cat >"$HOME/.config/beast/beast.conf" <<CONF
HOST_NAME=\$(touch $TMP/pwned)
PATH=/nowhere
CONF
  load_config 2>"$TMP/err"
  [ "$HOST_NAME" = "\$(touch $TMP/pwned)" ]
  [ ! -e "$TMP/pwned" ]
  [ "$PATH" != /nowhere ]
  grep -q "unknown setting PATH" "$TMP/err"
}

@test "--config / BEAST_CONFIG picks another file" {
  printf 'HOST_NAME=other\n' >"$TMP/alt.conf"
  BEAST_CONFIG="$TMP/alt.conf"
  load_config
  [ "$HOST_NAME" = other ]
}

@test "non-interactive: prompts are never read; confirm needs --yes" {
  BEAST_NONINTERACTIVE=1
  refute interactive
  refute ask "Really?" </dev/null
  refute confirm "Really?" </dev/null
  BEAST_YES=1
  confirm "Really?" </dev/null
}

@test "confirm_safety: non-interactive only with --yes" {
  BEAST_NONINTERACTIVE=1 BEAST_YES=0
  refute confirm_safety "Go headless?"
  BEAST_YES=1
  confirm_safety "Go headless?"
}

@test "read_secret refuses without a terminal" {
  BEAST_NONINTERACTIVE=1
  refute read_secret pw "Password"
}

@test "manual_action records JSON and a readable line" {
  manual_action x.y 'Do "this"' https://example.com 2>/dev/null
  [ "$(cat "$BEAST_RUN_DIR/manual")" = '{"id":"x.y","instruction":"Do \"this\"","url":"https://example.com"}' ]
  grep -q 'Do "this" (https://example.com)' "$BEAST_RUN_DIR/manual.txt"
}

@test "run_cmd under --dry-run prints instead of running" {
  BEAST_DRY_RUN=1
  run run_cmd touch "$TMP/x"
  [ "$output" = "would run: touch $TMP/x" ]
  [ ! -e "$TMP/x" ]
}

@test "install_file copies when different, keeps a backup, and is idempotent" {
  printf 'new\n' >"$TMP/src"
  mkdir -p "$TMP/etc"
  printf 'old\n' >"$TMP/etc/f"
  install_file "$TMP/src" "$TMP/etc/f" 2>/dev/null
  [ "$(cat "$TMP/etc/f")" = new ]
  ls "$TMP"/etc/f.bak.* >/dev/null
  : >"$STATE/calls"
  install_file "$TMP/src" "$TMP/etc/f"
  [ ! -s "$STATE/calls" ]
}

@test "apt_missing lists only missing packages" {
  STUB_MISSING_PKGS="nvtop btop" run apt_missing git nvtop curl btop
  [ "$output" = "nvtop btop" ]
}

@test "ts_field reads tailscale status" {
  [ "$(ts_field BackendState)" = Running ]
  [ "$(ts_field Self.ID)" = nTEST123 ]
  [ "$(ts_field Self.KeyExpiry)" = "" ]
}

@test "headless_gate: Tailscale, ssh.socket and sleep must all be ready" {
  headless_gate
  STUB_TS_STATE=NeedsLogin run headless_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tailscale isn't Running"* ]]
  STUB_SSH_SOCKET=disabled run headless_gate
  [ "$status" -eq 1 ]
  STUB_SLEEP=enabled run headless_gate
  [ "$status" -eq 1 ]
}
