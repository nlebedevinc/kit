#!/usr/bin/env bats
# bin/beast-check: every check ID, with stubbed system commands.
# The stubs describe a healthy beast; STUB_* variables break one thing at a time.

load helpers

setup() { beast_setup; }
teardown() { beast_teardown; }

# expect ID STATUS [ENV=VALUE...]: under these stub settings, ID has STATUS.
expect() {
  local id=$1 want=$2 got
  shift 2
  got=$(env "$@" bash "$REPO_ROOT/bin/beast-check" --json </dev/null | jq -r --arg id "$id" '[.checks[] | select(.id == $id) | .status] | join(",")')
  if [ "$got" != "$want" ]; then
    echo "check $id with $*: expected '$want', got '$got'"
    return 1
  fi
}

@test "a healthy machine: no warnings or failures, exit 0" {
  run beast_check --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '.summary | [.warn, .fail]')" = '[0,0]' ]
}

@test "JSON output matches docs/json-schema/doctor.schema.json" {
  beast_check --json | validate doctor.schema.json
  STUB_GPU=fail STUB_STICKS=1 STUB_NO_PREV=1 beast_check --json | validate doctor.schema.json
}

@test "every documented check ID is reported" {
  local ids
  ids=$(beast_check --json | jq -r '.checks[].id' | sort | tr '\n' ' ')
  for id in ram.size ram.sticks ram.speed gpu cpu.temp ram.temp nvme.smart disk.root swap \
    watchdog panic.reboot hw.errors shutdown.previous services.failed net.wifi wifi.ifname.Home \
    net.internet clock.ntp tailscale tailscale.expiry svc.tailscaled svc.ssh.socket \
    svc.NetworkManager lights.boot boot.target sleep ssh.passwords os ghostty.terminfo; do
    [[ " $ids " == *" $id "* ]] || { echo "missing: $id"; return 1; }
  done
}

@test "hardware: ram.size, ram.sticks, ram.speed" {
  echo RAM_EXPECTED_STICKS=1 >"$TMP/one.conf"
  expect ram.size pass
  expect ram.sticks pass
  expect ram.sticks warn STUB_STICKS=1
  expect ram.sticks pass STUB_STICKS=1 BEAST_CONFIG="$TMP/one.conf"
  expect ram.speed pass
  expect ram.speed warn "STUB_SPEED=6000 MT/s"
  expect ram.speed warn STUB_SPEED=
}

@test "hardware: the single-stick message is the original one" {
  STUB_STICKS=1 run beast_check
  [[ "$output" == *"only 1 stick (single channel) - replace the faulty kit"* ]]
}

@test "hardware: gpu" {
  expect gpu pass
  expect gpu warn STUB_GPU_TEMP=85
  expect gpu fail STUB_GPU=fail
}

@test "hardware: gpu is skipped without an NVIDIA GPU" {
  mkdir -p "$TMP/bin"
  for c in "$REPO_ROOT"/tests/stubs/*; do [ "${c##*/}" = nvidia-smi ] || ln -s "$c" "$TMP/bin/"; done
  run env PATH="$TMP/bin:/usr/bin:/bin" STUB_NO_GPU=1 bash "$REPO_ROOT/bin/beast-check" --json --section hardware
  [ "$(printf '%s' "$output" | jq -r '.checks[] | select(.id=="gpu") | .status')" = skip ]
}

@test "hardware: gpu is skipped when neither lspci nor nvidia-smi exist" {
  mkdir -p "$TMP/bin"
  for c in "$REPO_ROOT"/tests/stubs/*; do case ${c##*/} in nvidia-smi | lspci) ;; *) ln -s "$c" "$TMP/bin/" ;; esac; done
  run env PATH="$TMP/bin:/usr/bin:/bin" bash "$REPO_ROOT/bin/beast-check" --json --section hardware
  [ "$(printf '%s' "$output" | jq -r '.checks[] | select(.id=="gpu") | .status')" = skip ]
}

@test "hardware: cpu.temp and ram.temp" {
  expect cpu.temp pass
  expect cpu.temp warn STUB_CPU_TEMP=90
  expect cpu.temp warn STUB_CPU_TEMP=
  expect ram.temp pass
  expect ram.temp warn STUB_RAM_TEMP=70
  expect ram.temp skip STUB_RAM_TEMP=
}

@test "storage: nvme.smart, disk.root, swap" {
  expect nvme.smart pass
  expect nvme.smart fail STUB_SMART=fail
  expect nvme.smart fail STUB_MEDIA_ERRORS=3
  expect disk.root pass
  expect disk.root warn STUB_DISK=91
  expect swap pass
  printf 'MemTotal: 32617068 kB\nSwapTotal: 2097148 kB\n' >"$TMP/small-swap"
  expect swap warn BEAST_MEMINFO="$TMP/small-swap"
}

@test "storage: nvme.smart warns when smartmontools is missing" {
  mkdir -p "$TMP/bin"
  for c in "$REPO_ROOT"/tests/stubs/*; do [ "${c##*/}" = smartctl ] || ln -s "$c" "$TMP/bin/"; done
  run env PATH="$TMP/bin:/usr/bin:/bin" bash "$REPO_ROOT/bin/beast-check" --json --section storage
  [ "$(printf '%s' "$output" | jq -r '.checks[] | select(.id=="nvme.smart") | .status')" = warn ]
}

@test "stability: watchdog, panic.reboot, hw.errors" {
  expect watchdog pass
  expect watchdog warn STUB_WATCHDOG=0
  expect watchdog warn STUB_WATCHDOG=infinity
  expect panic.reboot pass
  expect panic.reboot warn STUB_PANIC=0
  expect hw.errors pass
  expect hw.errors fail STUB_MCE=1
}

@test "stability: shutdown.previous and services.failed" {
  expect shutdown.previous pass
  expect shutdown.previous warn STUB_UNCLEAN=1
  expect shutdown.previous skip STUB_NO_PREV=1
  expect services.failed pass
  expect services.failed pass STUB_FAILED=sssd-kcm.service
  expect services.failed warn STUB_FAILED=foo.service
}

@test "network: net.ethernet / net.wifi" {
  expect net.wifi pass
  expect net.ethernet "" STUB_NET=wifi
  expect net.ethernet pass STUB_NET=eth
  expect net.wifi "" STUB_NET=eth
  expect net.ethernet fail STUB_NET=none
}

@test "network: wifi.ifname.<name>" {
  expect wifi.ifname.Home pass
  expect wifi.ifname.Home warn STUB_IFNAME=wlp129s0f0
}

@test "network: net.internet, clock.ntp" {
  expect net.internet pass
  expect net.internet fail STUB_PING=fail
  expect clock.ntp pass
  expect clock.ntp warn STUB_NTP=no
}

@test "network: tailscale and tailscale.expiry" {
  expect tailscale pass
  expect tailscale fail STUB_TS_STATE=NeedsLogin
  expect tailscale.expiry pass
  expect tailscale.expiry warn STUB_TS_EXPIRY=2027-05-14T00:00:00Z
  expect tailscale.expiry skip STUB_TS_STATE=Stopped
}

@test "services: svc.<unit>" {
  expect svc.tailscaled pass
  expect svc.ssh.socket fail STUB_INACTIVE=ssh.socket
  expect svc.NetworkManager fail STUB_INACTIVE=NetworkManager
}

@test "services: lights.boot follows LIGHTS_BOOT" {
  echo LIGHTS_BOOT=hardware >"$TMP/hw.conf"
  expect lights.boot pass
  expect lights.boot warn STUB_LIGHTS=disabled
  expect lights.boot skip STUB_LIGHTS=not-found
  expect lights.boot pass STUB_LIGHTS=disabled BEAST_CONFIG="$TMP/hw.conf"
  expect lights.boot warn STUB_LIGHTS=enabled BEAST_CONFIG="$TMP/hw.conf"
}

@test "services: boot.target, sleep, ssh.passwords, os" {
  expect boot.target pass
  expect boot.target warn STUB_DEFAULT=graphical.target
  expect sleep pass
  expect sleep warn STUB_SLEEP=enabled
  expect ssh.passwords pass
  expect ssh.passwords warn STUB_SSH_PA=yes
  expect ssh.passwords warn STUB_SSH_ROOT=prohibit-password
  expect os pass
  printf 'ID=debian\nVERSION_ID="13"\n' >"$TMP/debian"
  expect os warn BEAST_OS_RELEASE="$TMP/debian"
}

@test "client: ghostty.terminfo, with the fix command for the configured host" {
  expect ghostty.terminfo pass
  expect ghostty.terminfo warn STUB_TERMINFO=missing
  STUB_TERMINFO=missing run beast_check
  [[ "$output" == *"infocmp -x xterm-ghostty | ssh me@beast -- tic -x -"* ]]
}

@test "exit codes: 1 on any failure; --strict makes warnings exit 3" {
  STUB_PING=fail run beast_check
  [ "$status" -eq 1 ]
  STUB_STICKS=1 run beast_check
  [ "$status" -eq 0 ]
  STUB_STICKS=1 run beast_check --strict
  [ "$status" -eq 3 ]
  run beast_check --strict
  [ "$status" -eq 0 ]
}

@test "--section runs one section" {
  run beast_check --json --section storage
  [ "$(printf '%s' "$output" | jq -r '[.checks[].section] | unique | join(",")')" = storage ]
  run beast_check --section nope
  [ "$status" -eq 2 ]
}

@test "human output: the original table, --ascii marks, no colors without a TTY" {
  run beast_check
  [[ "$output" == *"beast-check"* ]]
  [[ "$output" == *"✔ RAM speed"*"Standard (XMP off)"* ]]
  [[ "$output" == *"passed, 0 warnings, 0 failed"* ]]
  [[ "$output" != *$'\e['* ]]
  STUB_STICKS=1 run beast_check --ascii
  [[ "$output" == *"OK   RAM speed"* ]]
  [[ "$output" == *"WARN RAM sticks"* ]]
  [[ "$output" != *"✔"* ]]
}

@test "re-runs itself with sudo; non-interactive without cached sudo exits 5" {
  : >"$STATE/calls"
  beast_check >/dev/null
  grep -q "sudo -n true" "$STATE/calls"
  grep -q "beast-check --sudoed" "$STATE/calls"
  STUB_SUDO_NOPASS=1 run beast_check
  [ "$status" -eq 5 ]
  [[ "$output" == *'sudo -v'* ]]
}

@test "the config is passed through sudo and read as data" {
  mkdir -p "$HOME/.config/beast"
  printf 'HOST_NAME=box\nHOST_USER=bob\nPATH=/x\n' >"$HOME/.config/beast/beast.conf"
  STUB_TERMINFO=missing run beast_check
  [[ "$output" == *"ssh bob@box"* ]]
}
