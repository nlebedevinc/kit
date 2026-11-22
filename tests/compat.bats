#!/usr/bin/env bats
# Everything the earlier kit version's install did keeps working (see README, "Coming from kit").

load helpers

setup() { beast_setup; }
teardown() { beast_teardown; }

status_of() { printf '%s\n' "$output" | grep "\"id\":\"$1\"" | jq -r .status; }

@test "--host beast (the old one-liner) is accepted; another name is a usage error" {
  run beast --host beast plan
  [ "$status" -eq 0 ]
  run beast plan --host=beast
  [ "$status" -eq 0 ]
  run beast --host laptop plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"sets up 'beast'"* ]]
}

@test "install.sh passes --host through" {
  # shellcheck disable=SC2016  # a literal line of install.sh
  grep -q 'exec bash "$path/bin/beast" install "$@"' "$REPO_ROOT/install.sh"
}

@test "a non-Ubuntu system is refused, except with --dry-run" {
  printf 'ID=debian\nVERSION_ID="13"\n' >"$BEAST_OS_RELEASE"
  run beast install base-packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"not Ubuntu"* ]]
  run beast plan
  [ "$status" -eq 0 ]
}

@test "a hostname other than HOST_NAME is a warning, not a rename" {
  run beast plan
  [[ "$output" == *"but the config expects 'beast'"* ]] || [ "$(hostname)" = beast ]
  refute grep -q hostnamectl "$STATE/calls"
}

@test "update upgrades the system even when every package is installed" {
  run env BEAST_UPGRADE=1 bash "$REPO_ROOT/bin/beast" install base-packages --json </dev/null
  [ "$(status_of 10-base-packages)" = applied ]
  grep -q 'apt-get -y -o Dpkg::Options::=--force-confold full-upgrade' "$STATE/calls"
  grep -q 'export BEAST_UPGRADE=1' "$REPO_ROOT/bin/beast"
}

@test "BASE_PACKAGES comes from the config" {
  mkdir -p "$HOME/.config/beast"
  echo 'BASE_PACKAGES="git htop"' >"$HOME/.config/beast/beast.conf"
  run env STUB_MISSING_PKGS=htop bash "$REPO_ROOT/bin/beast" install base-packages --json </dev/null
  grep -q 'apt-get -y -o Dpkg::Options::=--force-confold install git htop$' "$STATE/calls"
}

@test "uninstall headless allows sleep again and boots to the desktop" {
  run beast uninstall headless --yes
  [ "$status" -eq 0 ]
  grep -q 'systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target' "$STATE/calls"
  grep -q 'systemctl set-default graphical.target' "$STATE/calls"
}

@test "config shows the settings in effect and hides secrets" {
  mkdir -p "$HOME/.config/beast"
  echo 'LIGHTS_BOOT=hardware' >"$HOME/.config/beast/beast.conf"
  run env TAILSCALE_AUTHKEY=tskey-TESTONLY-x bash "$REPO_ROOT/bin/beast" config </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIGHTS_BOOT=hardware"* ]]
  [[ "$output" == *"HOST_NAME=beast"* ]]
  [[ "$output" == *"TAILSCALE_AUTHKEY: set in the environment (hidden)"* ]]
  [[ "$output" != *tskey-TESTONLY-x* ]]
  run env TAILSCALE_AUTHKEY=tskey-TESTONLY-x bash "$REPO_ROOT/bin/beast" config --json </dev/null
  [ "$(printf '%s' "$output" | jq -c '[.values.LIGHTS_BOOT, .secrets.TAILSCALE_AUTHKEY, .secrets.WIFI_PSK]')" = '["hardware",true,false]' ]
}

@test "settings in the old ~/.config/kit/kit.conf are carried over" {
  mkdir -p "$HOME/.config/kit"
  printf '# old\nLIGHTS_BOOT=hardware   # keep the rainbow\nWIFI_CONNECTION="Home 5G"\nKIT_MODULES="a b"\n' >"$HOME/.config/kit/kit.conf"
  run beast install base-packages
  grep -qx 'LIGHTS_BOOT=hardware   # keep the rainbow' "$HOME/.config/beast/beast.conf"
  grep -qx 'WIFI_CONNECTION="Home 5G"' "$HOME/.config/beast/beast.conf"
  refute grep -q KIT_MODULES "$HOME/.config/beast/beast.conf"
  grep -qx 'HOST_NAME=beast' "$HOME/.config/beast/beast.conf"
  [[ "$output" == *"not carried over"*"KIT_MODULES"* ]]
}

@test "LIGHTS_BOOT must be off or hardware" {
  mkdir -p "$HOME/.config/beast"
  echo 'LIGHTS_BOOT=maybe' >"$HOME/.config/beast/beast.conf"
  run beast install lights --json
  [ "$(status_of 80-lights)" = failed ]
  [[ "$output" == *"LIGHTS_BOOT must be off or hardware"* ]]
}

# The kit-era lights files live in /etc and /usr/local; point the module at temp files.
lights_module() {
  bash -c '
    BEAST_ROOT=$1; . "$1/lib/output.sh"; . "$1/lib/common.sh"; load_config
    . "$1/modules/80-lights.sh"
    KIT_BIN=$2/kit-lights KIT_UNIT_DEST=$2/kit-lights-off.service KIT_CONF=$2/lights.conf
    shift 2; "$@"' _ "$REPO_ROOT" "$TMP/old" "$@" </dev/null
}

@test "the kit-era lights setup is removed after confirmation" {
  mkdir -p "$TMP/old"
  touch "$TMP/old/kit-lights" "$TMP/old/kit-lights-off.service" "$TMP/old/lights.conf"
  run lights_module kit_setup_present
  [ "$status" -eq 0 ]
  BEAST_YES=1 run lights_module remove_kit_setup
  [ "$status" -eq 0 ]
  grep -q 'systemctl disable kit-lights-off.service' "$STATE/calls"
  [ ! -e "$TMP/old/kit-lights" ] && [ ! -e "$TMP/old/kit-lights-off.service" ] && [ ! -e "$TMP/old/lights.conf" ]
}

@test "without --yes and a TTY, the kit-era lights setup stays and becomes a manual action" {
  mkdir -p "$TMP/old" "$TMP/run"
  touch "$TMP/old/kit-lights"
  BEAST_RUN_DIR="$TMP/run" run lights_module remove_kit_setup
  [ "$status" -eq 1 ]
  [ -e "$TMP/old/kit-lights" ]
  grep -q lights.kit_setup "$TMP/run/manual"
}
