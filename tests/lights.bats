#!/usr/bin/env bats
# bin/lights: openrgb command construction, against a fake openrgb.

load helpers

setup() {
  beast_setup
  mkdir -p "$HOME/.config/beast"
  printf 'OPENRGB_BIN=%s\n' "$REPO_ROOT/tests/stubs/openrgb" >"$HOME/.config/beast/beast.conf"
  O="$REPO_ROOT/tests/stubs/openrgb --noautoconnect"
}
teardown() { beast_teardown; }

MSI_OFF="-m Direct -z 0 -sz 120 -c 000000 -z 1 -sz 120 -c 000000 -z 2 -sz 120 -c 000000 -z 3 -sz 120 -c 000000"

@test "off, four devices (log §8.1): one call, then the GPU fallback" {
  run lights --dry-run off
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$O -d 0 -m Off -d 1 -m Off -d 2 -m Direct -c 000000 -d 3 $MSI_OFF" ]
  [ "${lines[1]}" = "$O -d 2 -m Static -c 000000 -b 0" ]
  [ "${lines[2]}" = "Lights off" ]
}

@test "off, one RAM stick: indices shift and still resolve by name" {
  STUB_DEVICES=one-ram run lights --dry-run off
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$O -d 0 -m Off -d 1 -m Direct -c 000000 -d 2 $MSI_OFF" ]
  [ "${lines[1]}" = "$O -d 1 -m Static -c 000000 -b 0" ]
}

@test "on: RAM rainbow, GPU and motherboard white" {
  run lights --dry-run on
  [ "${lines[0]}" = "$O -d 0 -m Rainbow -d 1 -m Rainbow -d 2 -m Static -c FFFFFF -b 100 -d 3 -m Direct -z 0 -sz 120 -c FFFFFF -z 1 -sz 120 -c FFFFFF -z 2 -sz 120 -c FFFFFF -z 3 -sz 120 -c FFFFFF" ]
}

@test "a color applies to every device, uppercased" {
  STUB_DEVICES=one-ram run lights --dry-run 00aaff
  [ "${lines[0]}" = "$O -d 0 -m Static -c 00AAFF -d 1 -m Static -c 00AAFF -b 100 -d 2 -m Direct -z 0 -sz 120 -c 00AAFF -z 1 -sz 120 -c 00AAFF -z 2 -sz 120 -c 00AAFF -z 3 -sz 120 -c 00AAFF" ]
  [ "${lines[1]}" = "Lights set to #00AAFF" ]
}

@test "the MSI zone size always comes before the color in the same call" {
  run lights --dry-run 123456
  [[ "${lines[0]}" =~ -z\ 3\ -sz\ 120\ -c\ 123456$ ]]
}

@test "zero RAM devices: no RAM arguments" {
  printf 'LIGHTS_RAM_DEVICES="Nope"\n' >>"$HOME/.config/beast/beast.conf"
  run lights --dry-run off
  [ "$status" -eq 0 ]
  [[ "${lines[*]}" == *"-d 2 -m Direct -c 000000 -d 3 -m Direct"* ]]
  [[ "${lines[*]}" != *"-m Off"* ]]
}

@test "zones and sizes come from the config" {
  printf 'LIGHTS_MB_ZONES="1 3"\nLIGHTS_MB_ZONE_SIZE=60\n' >>"$HOME/.config/beast/beast.conf"
  run lights --dry-run FF0000
  [[ "${lines[0]}" == *"-d 3 -m Direct -z 1 -sz 60 -c FF0000 -z 3 -sz 60 -c FF0000" ]]
}

@test "really runs one openrgb call for on (plus the -l scan)" {
  run lights on
  [ "$status" -eq 0 ]
  [ "$(grep -vc ' -l' "$STATE/openrgb.calls")" -eq 1 ]
  grep -q -- '--noautoconnect -l' "$STATE/openrgb.calls"
}

@test "status --json maps devices" {
  run lights --json status
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '[.ram, .gpu, .motherboard]')" = '[[0,1],2,3]' ]
  STUB_DEVICES=one-ram run lights --json status
  [ "$(printf '%s' "$output" | jq -c '[.ram, .gpu, .motherboard]')" = '[[0],1,2]' ]
}

@test "no devices: a clear error" {
  STUB_DEVICES=none run lights off
  [ "$status" -eq 1 ]
  [[ "$output" == *"no RGB devices found"* ]]
}

@test "bad input is rejected; --help mentions the rainbow limitation" {
  run lights purple
  [ "$status" -eq 1 ]
  run lights
  [ "$status" -eq 2 ]
  run lights --help
  [[ "$output" == *"built-in rainbow"* ]]
  [[ "$output" == *"docs/troubleshooting.md"* ]]
}
