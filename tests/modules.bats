#!/usr/bin/env bats
# Module behavior through `beast install`: idempotency, safety gates, secrets.
# Files written through the fake sudo land in $FAKEROOT.

load helpers

setup() { beast_setup; }
teardown() { beast_teardown; }

status_of() { printf '%s\n' "$output" | grep "\"id\":\"$1\"" | jq -r .status; }

@test "ssh: with a key, the drop-in is installed, validated, then ssh restarted" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTONLY me@mac" >"$HOME/.ssh/authorized_keys"
  run beast install ssh --json
  [ "$(status_of 40-ssh)" = applied ]
  cmp "$REPO_ROOT/config/ssh/99-hardening.conf" "$FAKEROOT/etc/ssh/sshd_config.d/99-hardening.conf"
  grep -n 'sshd -t' "$STATE/calls" | head -n 1 | cut -d: -f1 >"$TMP/t"
  grep -n 'systemctl restart ssh' "$STATE/calls" | head -n 1 | cut -d: -f1 >"$TMP/r"
  [ "$(cat "$TMP/t")" -lt "$(cat "$TMP/r")" ]
}

@test "ssh: a config sshd -t rejects is rolled back and ssh isn't restarted" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTONLY me@mac" >"$HOME/.ssh/authorized_keys"
  run env STUB_SSHD_T=255 bash "$REPO_ROOT/bin/beast" install ssh --json </dev/null
  [ "$status" -eq 1 ]
  [ "$(status_of 40-ssh)" = failed ]
  [ ! -e "$FAKEROOT/etc/ssh/sshd_config.d/99-hardening.conf" ]
  refute grep -q 'systemctl restart ssh' "$STATE/calls"
}

@test "headless: blocked unless the gate passes (ssh.socket here), even with --yes" {
  run env STUB_SSH_SOCKET=disabled STUB_DEFAULT=graphical.target \
    bash "$REPO_ROOT/bin/beast" install headless --yes --json </dev/null
  [ "$status" -eq 4 ]
  [ "$(status_of 60-headless)" = blocked ]
  refute grep -q 'set-default' "$STATE/calls"
}

@test "headless: non-interactive without --yes is a manual action" {
  run env STUB_DEFAULT=graphical.target bash "$REPO_ROOT/bin/beast" install headless --json </dev/null
  [ "$(status_of 60-headless)" = manual ]
  refute grep -q 'set-default' "$STATE/calls"
}

@test "headless: with --yes and the gate passed, switches and reports reboot_required" {
  run env STUB_DEFAULT=graphical.target bash "$REPO_ROOT/bin/beast" install headless --yes --json </dev/null
  [ "$(status_of 60-headless)" = applied ]
  grep -q 'systemctl set-default multi-user.target' "$STATE/calls"
  [ "$(summary_line | jq -r .reboot_required)" = true ]
  refute grep -qE 'reboot$|systemctl reboot' "$STATE/calls"
}

@test "tailscale: the auth key goes on stdin, never on a command line" {
  run env STUB_TS_STATE=NeedsLogin TAILSCALE_AUTHKEY=tskey-TESTONLY-secret \
    bash "$REPO_ROOT/bin/beast" install tailscale --json </dev/null
  grep -q 'tailscale up --auth-key=file:/dev/stdin' "$STATE/calls"
  [ "$(cat "$STATE/tailscale-up.stdin")" = tskey-TESTONLY-secret ]
  refute grep -rq 'tskey-TESTONLY-secret' "$STATE/calls" "$HOME/.local/state/beast"
  [[ "$output" != *tskey-TESTONLY-secret* ]]
}

@test "tailscale: key expiry is disabled through the API with the token on stdin" {
  run env STUB_TS_EXPIRY=2027-05-14T00:00:00Z TS_API_TOKEN=tskey-api-TESTONLY \
    bash "$REPO_ROOT/bin/beast" install tailscale --json </dev/null
  grep -q 'curl --config - .*api.tailscale.com/api/v2/device/nTEST123/key' "$STATE/calls"
  refute grep -rq 'tskey-api-TESTONLY' "$STATE/calls" "$HOME/.local/state/beast"
  [[ "$output" != *tskey-api-TESTONLY* ]]
}

@test "reliability: writes the log's files and applies them without a reboot" {
  run env STUB_WATCHDOG=0 STUB_PANIC=0 bash "$REPO_ROOT/bin/beast" install reliability --json </dev/null
  cmp "$REPO_ROOT/config/systemd/watchdog.conf" "$FAKEROOT/etc/systemd/system.conf.d/watchdog.conf"
  cmp "$REPO_ROOT/config/sysctl/99-panic-reboot.conf" "$FAKEROOT/etc/sysctl.d/99-panic-reboot.conf"
  grep -q 'systemctl daemon-reexec' "$STATE/calls"
  grep -q 'sysctl --system' "$STATE/calls"
  [ "$(summary_line | jq -r .reboot_required)" = false ]
}

@test "reliability: values come from the config" {
  mkdir -p "$HOME/.config/beast"
  printf 'WATCHDOG_SEC=60\nPANIC_REBOOT_SEC=20\n' >"$HOME/.config/beast/beast.conf"
  run env STUB_WATCHDOG=0 bash "$REPO_ROOT/bin/beast" install reliability --json </dev/null
  grep -qx 'RuntimeWatchdogSec=60s' "$FAKEROOT/etc/systemd/system.conf.d/watchdog.conf"
  grep -qx 'kernel.panic = 20' "$FAKEROOT/etc/sysctl.d/99-panic-reboot.conf"
}

@test "wifi and openrgb/lights are skipped without the hardware" {
  run env STUB_NET=eth STUB_NO_RGB=1 bash "$REPO_ROOT/bin/beast" install wifi openrgb lights --json </dev/null
  [ "$(status_of 50-wifi)" = skipped ]
  [ "$(status_of 70-openrgb)" = skipped ]
  [ "$(status_of 80-lights)" = skipped ]
}

@test "lights: installs the script, the unit and enables it (LIGHTS_BOOT=off)" {
  run env STUB_LIGHTS=disabled bash "$REPO_ROOT/bin/beast" install lights --json </dev/null
  cmp "$REPO_ROOT/bin/lights" "$FAKEROOT/usr/local/bin/lights"
  cmp "$REPO_ROOT/config/systemd/lights-off.service" "$FAKEROOT/etc/systemd/system/lights-off.service"
  grep -q 'systemctl enable lights-off.service' "$STATE/calls"
}

@test "lights: LIGHTS_BOOT=hardware disables the boot service" {
  mkdir -p "$HOME/.config/beast"
  echo LIGHTS_BOOT=hardware >"$HOME/.config/beast/beast.conf"
  run beast install lights --json
  grep -q 'systemctl disable lights-off.service' "$STATE/calls"
}

@test "uninstall shows what will be removed and needs --yes without a TTY" {
  run beast uninstall lights
  [ "$status" -eq 3 ]
  [[ "$output" == *"would run: sudo rm -f /etc/systemd/system/lights-off.service"* ]]
  refute grep -q '^sudo rm' "$STATE/calls"
  run beast uninstall lights --yes
  [ "$status" -eq 0 ]
  grep -q 'sudo rm -f /etc/systemd/system/lights-off.service' "$STATE/calls"
}

@test "the install log gets the run, never a secret" {
  run env STUB_TS_STATE=NeedsLogin TAILSCALE_AUTHKEY=tskey-TESTONLY-secret WIFI_PSK=TESTONLY-hunter2 \
    bash "$REPO_ROOT/bin/beast" install --json </dev/null
  [ -s "$HOME/.local/state/beast/install.log" ]
  refute grep -q 'TESTONLY' "$HOME/.local/state/beast/install.log"
}
