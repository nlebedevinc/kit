#!/usr/bin/env bats
# The real beast modules against fake system commands (tests/stubs), in dry-run mode:
# safety gates block when they should, and secrets never reach the output.

load helpers

setup() {
  kit_setup
  cp -R "$REPO_ROOT/modules" "$ROOT/"
  rm -rf "$ROOT/hosts"
  mkdir -p "$ROOT/hosts"
  cp -R "$REPO_ROOT/hosts/beast" "$ROOT/hosts/"
  STUBSTATE="$TMP/stubstate"
  mkdir -p "$STUBSTATE"
  export STUBSTATE
  export PATH="$REPO_ROOT/tests/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
}
teardown() { kit_teardown; }

add_key() {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnlyFakeKeyForTests test" >"$HOME/.ssh/authorized_keys"
}

no_side_effects() { [ ! -s "$STUBSTATE/side-effects" ]; }

@test "ssh: without an authorized key, hardening is blocked (exit 3) and nothing is installed" {
  run kit --host beast --dry-run install ssh
  [ "$status" -eq 3 ]
  [[ "$output" == *"No key in ~/.ssh/authorized_keys"* ]]
  [[ "$output" == *"ssh-copy-id me@beast"* ]]
  [[ "$output" != *"99-hardening.conf /etc/ssh"* ]]
  no_side_effects
}

@test "ssh: with a key, over SSH, the dry run shows install, validate and restart" {
  add_key
  export SSH_CONNECTION="10.0.0.2 5000 10.0.0.1 22"
  run kit --host beast --dry-run install ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] sudo install -m 644 "*"99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf"* ]]
  [[ "$output" == *"sshd -t"* ]]
  [[ "$output" == *"[dry-run] sudo systemctl restart ssh"* ]]
  no_side_effects
}

@test "ssh: a locally run real install with a key still needs a confirmation that --yes can't give" {
  add_key
  touch "$STUBSTATE/pkg.openssh-server" "$STUBSTATE/unit.ssh.socket"
  echo enabled >"$STUBSTATE/enabled.ssh.socket"
  export KIT_SKIP_SUDO=1
  run kit --host beast --yes install ssh
  # The OS check stops non-dry runs off Ubuntu; on Ubuntu CI the gate must block.
  if [ "$(uname -s)" = Linux ]; then
    [ "$status" -eq 3 ]
    [[ "$output" == *"no terminal to ask"* ]]
  else
    [ "$status" -eq 1 ]
  fi
  no_side_effects
}

@test "headless: blocked while Tailscale is down" {
  echo enabled >"$STUBSTATE/enabled.ssh.socket"
  run kit --host beast --dry-run install headless
  [ "$status" -eq 3 ]
  [[ "$output" == *"Tailscale isn't connected"* ]]
  [[ "$output" != *"set-default multi-user.target"* ]]
}

@test "headless: blocked while SSH is off" {
  touch "$STUBSTATE/tailscale.up"
  run kit --host beast --dry-run install headless
  [ "$status" -eq 3 ]
  [[ "$output" == *"SSH isn't enabled"* ]]
}

@test "headless: with Tailscale and SSH up, the dry run masks sleep and switches the target, asking before reboot" {
  touch "$STUBSTATE/tailscale.up"
  echo enabled >"$STUBSTATE/enabled.ssh.socket"
  run kit --host beast --dry-run install headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target"* ]]
  [[ "$output" == *"[dry-run] sudo systemctl set-default multi-user.target"* ]]
  [[ "$output" == *"would ask before rebooting"* ]]
  [[ "$output" != *"systemctl reboot"* ]]
}

@test "wifi: the dry run never asks for or shows the password" {
  run kit --host beast --dry-run install wifi
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wi-Fi connection: Home:Net"* ]]
  [[ "$output" == *"would ask for the Wi-Fi password"* ]]
  [[ "$output" != *"wifi-sec.psk"* ]]
  [[ "$output" != *"802-11-wireless-security.psk "* ]]
  [[ "$output" == *"[dry-run] sudo nmcli connection modify Home:Net connection.permissions '' connection.autoconnect yes"* ]]
  no_side_effects
}

@test "tailscale: the auth key never appears in output" {
  export TAILSCALE_AUTHKEY=tskey-auth-TESTONLY1234567890
  run kit --host beast --dry-run --verbose install tailscale
  [ "$status" -eq 0 ]
  [[ "$output" != *"TESTONLY1234567890"* ]]
  [[ "$output" == *"tailscale up --authkey=***"* ]]
  run kit --host beast config
  [[ "$output" != *"TESTONLY1234567890"* ]]
  [[ "$output" == *"TAILSCALE_AUTHKEY=<hidden"* ]]
}

@test "openrgb: the dry run downloads over https and checks the pinned checksum" {
  run kit --host beast --dry-run install openrgb
  [ "$status" -eq 0 ]
  [[ "$output" == *"modprobe -a i2c-dev i2c-i801"* ]]
  [[ "$output" == *"curl -fL --proto =https"*"codeberg.org/OpenRGB"* ]]
  [[ "$output" == *"would check SHA-256 d556c227"* ]]
  [[ "$output" == *"--generate-udev-rules /etc/udev/rules.d/60-openrgb.rules"* ]]
}

@test "lights: LIGHTS_BOOT=hardware leaves the boot service disabled" {
  export LIGHTS_BOOT=hardware
  run kit --host beast --dry-run install lights
  [ "$status" -eq 0 ]
  [[ "$output" != *"systemctl enable kit-lights-off.service"* ]]
  [[ "$output" == *"LIGHTS_BOOT=hardware"* ]]
}

@test "lights: LIGHTS_BOOT=off enables the boot service" {
  run kit --host beast --dry-run install lights
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] sudo systemctl enable kit-lights-off.service"* ]]
  [[ "$output" == *"[dry-run] sudo install -m 755 "*"commands/lights /usr/local/bin/kit-lights"* ]]
}

@test "the full beast dry run finishes with nothing failed" {
  touch "$STUBSTATE/tailscale.up"
  echo enabled >"$STUBSTATE/enabled.ssh.socket"
  add_key
  export SSH_CONNECTION="10.0.0.2 5000 10.0.0.1 22"
  run kit --host beast --dry-run --yes install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary:"* ]]
  [[ "$output" != *"failed:"* ]]
  no_side_effects
}
