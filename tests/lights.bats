#!/usr/bin/env bats
# hosts/beast/commands/lights: argument handling and the exact openrgb calls.

load helpers

setup() {
  kit_setup
  LIGHTS="$REPO_ROOT/hosts/beast/commands/lights"
  printf 'OPENRGB_BIN=%q\n' "$REPO_ROOT/tests/stubs/openrgb" >"$STATE/lights.conf"
  export KIT_LIGHTS_CONF="$STATE/lights.conf"
}
teardown() { kit_teardown; }

lights() { "$TEST_BASH" "$LIGHTS" "$@"; }
calls() { grep '^SET ' "$STATE/openrgb.calls" | sed 's/^SET //'; }

MSI_BLACK='-d 3 -m Direct -z 0 -sz 120 -c 000000 -z 1 -sz 120 -c 000000 -z 2 -sz 120 -c 000000 -z 3 -sz 120 -c 000000'

@test "off: one call for everything, then the GPU fallback (same as the setup log)" {
  run lights off
  [ "$status" -eq 0 ]
  [ "$output" = "Lights off" ]
  [ "$(calls | sed -n 1p)" = "--noautoconnect -d 0 -m Off -d 1 -m Off -d 2 -m Direct -c 000000 $MSI_BLACK" ]
  [ "$(calls | sed -n 2p)" = "--noautoconnect -d 2 -m Static -c 000000 -b 0" ]
  [ "$(calls | wc -l | tr -d ' ')" = 2 ]
}

@test "on: RAM rainbow, GPU and motherboard white" {
  run lights on
  [ "$status" -eq 0 ]
  [ "$(calls)" = "--noautoconnect -d 0 -m Rainbow -d 1 -m Rainbow -d 2 -m Static -c FFFFFF -b 100 -d 3 -m Direct -z 0 -sz 120 -c FFFFFF -z 1 -sz 120 -c FFFFFF -z 2 -sz 120 -c FFFFFF -z 3 -sz 120 -c FFFFFF" ]
}

@test "a color sets everything, lowercase accepted" {
  run lights 00aaff
  [ "$status" -eq 0 ]
  [ "$output" = "Lights set to #00AAFF" ]
  [ "$(calls)" = "--noautoconnect -d 0 -m Static -c 00AAFF -d 1 -m Static -c 00AAFF -d 2 -m Static -c 00AAFF -b 100 -d 3 -m Direct -z 0 -sz 120 -c 00AAFF -z 1 -sz 120 -c 00AAFF -z 2 -sz 120 -c 00AAFF -z 3 -sz 120 -c 00AAFF" ]
}

@test "devices are found by name, not by fixed index" {
  export STUB_ORDER=reversed
  run lights 112233
  [ "$status" -eq 0 ]
  [ "$(calls)" = "--noautoconnect -d 2 -m Static -c 112233 -d 3 -m Static -c 112233 -d 1 -m Static -c 112233 -b 100 -d 0 -m Direct -z 0 -sz 120 -c 112233 -z 1 -sz 120 -c 112233 -z 2 -sz 120 -c 112233 -z 3 -sz 120 -c 112233" ]
}

@test "the device list is always read with --noautoconnect" {
  lights off >/dev/null
  grep -q '^LIST --noautoconnect -l' "$STATE/openrgb.calls"
}

@test "zone list and size come from the config" {
  printf 'LIGHTS_MB_ZONES="1 3"\nLIGHTS_MB_ZONE_SIZE=60\n' >>"$STATE/lights.conf"
  run lights FF0000
  [[ "$(calls)" == *"-d 3 -m Direct -z 1 -sz 60 -c FF0000 -z 3 -sz 60 -c FF0000" ]]
}

@test "invalid colors and extra arguments are rejected without calling openrgb" {
  run lights GG0000
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a color"* ]]
  run lights 12345
  [ "$status" -eq 1 ]
  run lights on off
  [ "$status" -eq 1 ]
  [ ! -f "$STATE/openrgb.calls" ]
}

@test "--dry-run prints the call instead of running it" {
  run lights --dry-run off
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] "*"--noautoconnect -d 0 -m Off"* ]]
  ! grep -q '^SET ' "$STATE/openrgb.calls"
}

@test "no devices found is an error with a hint" {
  export STUB_ORDER=empty
  run lights off
  [ "$status" -eq 1 ]
  [[ "$output" == *"no RGB devices found"* ]]
}

@test "--help explains the rainbow limitation" {
  run lights --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"can't bring back the motherboard's built-in rainbow"* ]]
  [[ "$output" == *"troubleshooting.md"* ]]
}

@test "status shows the mapping" {
  run lights status
  [ "$status" -eq 0 ]
  [[ "$output" == *"GPU (\"GeForce\"):          2"* ]]
  [[ "$output" == *"Motherboard (\"MSI MYSTIC LIGHT\"): 3"* ]]
}
