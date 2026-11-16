#!/usr/bin/env bats
# lib/common.sh: dry-run, redaction, prompts without a terminal, file installs.

load helpers

setup() {
  kit_setup
  load_libs
}
teardown() { kit_teardown; }

@test "run_cmd executes the command normally" {
  run run_cmd touch "$STATE/made"
  [ "$status" -eq 0 ]
  [ -f "$STATE/made" ]
}

@test "run_cmd under --dry-run prints the command and doesn't execute it" {
  KIT_DRY_RUN=1
  run run_cmd touch "$STATE/made"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] touch $STATE/made"* ]]
  [ ! -e "$STATE/made" ]
}

@test "registered secrets never appear in printed commands" {
  KIT_DRY_RUN=1
  kit_secret 'tskey-abc123'
  kit_secret 'pa ss$word'
  run run_cmd tool --authkey=tskey-abc123 'pa ss$word'
  [[ "$output" != *"tskey-abc123"* ]]
  [[ "$output" != *"ss"*"word"* ]]
  [[ "$output" == *"--authkey=***"* ]]
}

@test "ask answers no when there's no terminal, even with default yes" {
  run ask "Proceed?" y
  [ "$status" -eq 1 ]
  [[ "$output" == *"no terminal"* ]]
}

@test "confirm answers yes with --yes" {
  KIT_YES=1
  run confirm "Proceed?"
  [ "$status" -eq 0 ]
}

@test "confirm_always ignores --yes" {
  KIT_YES=1
  run confirm_always "Reboot now?"
  [ "$status" -eq 1 ]
}

@test "read_secret fails without a terminal" {
  run read_secret PW "Password"
  [ "$status" -eq 1 ]
}

@test "install_file backs up a different existing file and leaves an identical one alone" {
  # Run as plain commands instead of sudo.
  run_sudo() { run_cmd "$@"; }
  printf 'new\n' >"$STATE/src"
  printf 'old\n' >"$STATE/dest"
  install_file "$STATE/src" "$STATE/dest"
  [ "$(cat "$STATE/dest")" = new ]
  ls "$STATE"/dest.bak.* >/dev/null
  run install_file "$STATE/src" "$STATE/dest"
  [[ "$output" == *"already up to date"* ]]
}

@test "os_release_value reads and unquotes values" {
  printf 'ID=ubuntu\nVERSION_ID="26.04"\n' >"$STATE/os-release"
  KIT_OS_RELEASE="$STATE/os-release"
  [ "$(os_release_value ID)" = ubuntu ]
  [ "$(os_release_value VERSION_ID)" = 26.04 ]
}

@test "report fail marks the result failed" {
  report ok "fine" >/dev/null
  report_status
  report fail "broken" "fix it" >/dev/null
  run report_status
  [ "$status" -eq 1 ]
}
