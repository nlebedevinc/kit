#!/usr/bin/env bats
# bin/beast: commands, JSON output, exit codes 0–6, non-interactive behavior.

load helpers

setup() { beast_setup; }
teardown() { beast_teardown; }

@test "help: beast --help and beast <command> --help" {
  run beast --help
  [ "$status" -eq 0 ]
  for c in install plan list doctor update gui uninstall describe; do [[ "$output" == *"$c"* ]]; done
  run beast install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"TAILSCALE_AUTHKEY"* ]]
  run beast doctor --help
  [[ "$output" == *"--strict"* ]]
}

@test "exit 2: usage errors" {
  run beast
  [ "$status" -eq 2 ]
  run beast frobnicate
  [ "$status" -eq 2 ]
  run beast --bogus list
  [ "$status" -eq 2 ]
  run beast install nosuchmodule
  [ "$status" -eq 2 ]
  run beast list --strict
  [ "$status" -eq 2 ]
  run beast uninstall tailscale
  [ "$status" -eq 2 ]
  run beast gui sideways
  [ "$status" -eq 2 ]
}

@test "describe --json matches its schema and lists everything an agent needs" {
  beast describe --json | validate describe.schema.json
  run beast describe --json
  [ "$(printf '%s' "$output" | jq '.modules | length')" -eq 11 ]
  [ "$(printf '%s' "$output" | jq -r '[.env[].name] | join(" ")')" = "TAILSCALE_AUTHKEY TS_API_TOKEN WIFI_PSK BEAST_NONINTERACTIVE NO_COLOR" ]
  [ "$(printf '%s' "$output" | jq -r '[.exit_codes[].code] | join(",")')" = "0,1,2,3,4,5,6" ]
  [ "$(printf '%s' "$output" | jq -r '.config.keys[] | select(.name=="LIGHTS_BOOT") | .default')" = off ]
  [ "$(printf '%s' "$output" | jq -r '[.modules[] | select(.uninstall) | .id] | join(" ")')" = "25-reliability 70-openrgb 80-lights" ]
}

@test "plan --json: NDJSON events matching the schema, nothing changed" {
  beast plan --json | validate events.schema.json ndjson
  run beast plan --json
  [ "$status" -eq 0 ]
  [ "$(summary_line | jq -r .type)" = summary ]
  [ "$(json_lines | head -n 1 | jq -r .id)" = 00-preflight ]
  [ "$(printf '%s\n' "$output" | grep -c '"type":"module"')" -eq 11 ]
  [ ! -e "$HOME/.config/beast/beast.conf" ]
  refute grep -q '^sudo' "$STATE/calls" 2>/dev/null
}

@test "plan lists the actions of modules that aren't applied" {
  run env STUB_MISSING_PKGS=nvtop bash "$REPO_ROOT/bin/beast" plan --json </dev/null
  printf '%s\n' "$output" | grep '"id":"10-base-packages"' | jq -e '.status == "planned" and (.actions | index("apt-get install -y nvtop"))'
}

@test "install --dry-run is the same as plan" {
  run beast install --dry-run --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"planned"'* ]]
}

@test "list shows each module's state" {
  run beast list
  [ "$status" -eq 0 ]
  [[ "$output" == *"30-tailscale"*"applied"* ]]
  run beast list --json
  [ "$(printf '%s' "$output" | jq -r '.modules[] | select(.id=="20-nvidia") | .status')" = applied ]
}

@test "exit 0: an install with nothing to do, then the health check" {
  run beast install base-packages --json
  [ "$status" -eq 0 ]
  json_lines | validate events.schema.json ndjson
  [ "$(printf '%s\n' "$output" | grep '"id":"10-base-packages"' | jq -r .status)" = already ]
  [ "$(summary_line | jq -c '[.ok, .exit_code, .doctor.fail]')" = '[true,0,0]' ]
  [ -f "$HOME/.config/beast/beast.conf" ]
}

@test "exit 1: a failing module (nvidia-smi broken)" {
  run env STUB_GPU=fail bash "$REPO_ROOT/bin/beast" install nvidia --json </dev/null
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep '"id":"20-nvidia"' | jq -r .status)" = failed ]
  [[ "$output" == *"ubuntu-drivers install"* ]]
}

@test "exit 1: a failing health check fails the install" {
  run env STUB_PING=fail bash "$REPO_ROOT/bin/beast" install base-packages --json </dev/null
  [ "$status" -eq 1 ]
  [ "$(summary_line | jq -r .doctor.fail)" -eq 1 ]
}

@test "warnings don't fail the install" {
  run env STUB_STICKS=1 bash "$REPO_ROOT/bin/beast" install base-packages --json </dev/null
  [ "$status" -eq 0 ]
}

@test "the Tailscale login without a TTY is a manual action with the URL" {
  run env STUB_TS_STATE=NeedsLogin STUB_TS_AUTHURL=https://login.tailscale.com/a/abc123 \
    bash "$REPO_ROOT/bin/beast" install tailscale --json </dev/null
  # 1, not 3: the health check also fails (Tailscale isn't Running yet), and failures win.
  [ "$status" -eq 1 ]
  local summary
  summary=$(summary_line)
  [ "$(printf '%s' "$summary" | jq -r '.manual_actions[0].id')" = tailscale.login ]
  [ "$(printf '%s' "$summary" | jq -r '.manual_actions[0].url')" = https://login.tailscale.com/a/abc123 ]
  [ "$(printf '%s\n' "$output" | grep '"id":"30-tailscale"' | jq -r .status)" = manual ]
}

@test "exit 3: key expiry still on, no API token" {
  run env STUB_TS_EXPIRY=2027-05-14T00:00:00Z bash "$REPO_ROOT/bin/beast" install tailscale --json </dev/null
  [ "$status" -eq 3 ]
  [ "$(summary_line | jq -r '.manual_actions[0].id')" = tailscale.key_expiry ]
}

@test "exit 4: blocked by the SSH safety gate (no authorized key)" {
  run env STUB_SSH_PA=yes bash "$REPO_ROOT/bin/beast" install ssh --json </dev/null
  [ "$status" -eq 4 ]
  [ "$(printf '%s\n' "$output" | grep '"id":"40-ssh"' | jq -r .status)" = blocked ]
  [ ! -e "$FAKEROOT/etc/ssh/sshd_config.d/99-hardening.conf" ]
  [[ "$output" == *"ssh-copy-id me@beast"* ]]
}

@test "exit 5: sudo needs a password and there's no TTY" {
  run env STUB_SUDO_NOPASS=1 bash "$REPO_ROOT/bin/beast" install base-packages </dev/null
  [ "$status" -eq 5 ]
  [[ "$output" == *'sudo -v'* ]]
  [[ "$output" == *'ssh -t'* ]]
}

@test "exit 6: another run holds the lock" {
  mkdir -p "$HOME/.local/state/beast"
  flock "$HOME/.local/state/beast/lock" sleep 5 &
  sleep 0.5
  run beast plan
  [ "$status" -eq 6 ]
  wait
}

@test "refuses to run as root" {
  grep -q 'require_not_root' "$REPO_ROOT/bin/beast"
  [ "$(id -u)" -ne 0 ] || skip "running as root"
}

@test "non-interactive: no command waits for input" {
  local c
  for c in "plan" "list" "describe" "describe --json" "doctor" "doctor --json" "install --non-interactive" \
    "install headless" "uninstall lights" "gui on" "--help"; do
    # shellcheck disable=SC2086
    run timeout 60 bash "$REPO_ROOT/bin/beast" $c </dev/null
    [ "$status" -ne 124 ] || { echo "hung: beast $c"; return 1; }
  done
}

@test "doctor runs beast-check and passes flags through" {
  run beast doctor --json --section client
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.checks[0].id')" = ghostty.terminfo ]
  run env STUB_STICKS=1 bash "$REPO_ROOT/bin/beast" doctor --strict </dev/null
  [ "$status" -eq 3 ]
}
