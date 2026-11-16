#!/usr/bin/env bats
# lib/config.sh: host resolution and config layering.

load helpers

setup() {
  kit_setup
  load_libs
  make_host otherbox
}
teardown() { kit_teardown; }

write_user_conf() {
  mkdir -p "$XDG_CONFIG_HOME/kit"
  printf '%s\n' "$@" >"$XDG_CONFIG_HOME/kit/kit.conf"
}

@test "resolve_host: --host wins over everything" {
  write_user_conf 'KIT_HOST=otherbox'
  KIT_HOST=otherbox
  [ "$(resolve_host testbox)" = testbox ]
}

@test "resolve_host: KIT_HOST env wins over user config" {
  write_user_conf 'KIT_HOST=testbox'
  KIT_HOST=otherbox
  [ "$(resolve_host '')" = otherbox ]
}

@test "resolve_host: user config is used when nothing else is given" {
  write_user_conf 'KIT_HOST=otherbox'
  [ "$(resolve_host '')" = otherbox ]
}

@test "resolve_host: falls back to the machine's hostname" {
  KIT_HOSTNAME=TestBox
  [ "$(resolve_host '')" = testbox ]
}

@test "resolve_host: no match and no terminal is a usage error" {
  run resolve_host ''
  [ "$status" -eq 2 ]
  [[ "$output" == *"Pass --host NAME"* ]]
  [[ "$output" == *"testbox"* ]]
}

@test "resolve_host: rejects unknown and path-like names" {
  run resolve_host nope
  [ "$status" -eq 2 ]
  run resolve_host ..
  [ "$status" -eq 2 ]
  run resolve_host ../testbox
  [ "$status" -eq 2 ]
}

@test "load_config: user config overrides host.conf" {
  write_user_conf 'GREETING=hi'
  load_config testbox
  [ "$GREETING" = hi ]
  [ "$KIT_HOST_DIR" = "$ROOT/hosts/testbox" ]
}

@test "load_config: environment overrides both files" {
  write_user_conf 'GREETING=hi'
  GREETING='from env'
  load_config testbox
  [ "$GREETING" = 'from env' ]
}

@test "load_config: works without a user config" {
  load_config testbox
  [ "$GREETING" = hello ]
  [ "$KIT_MODULES" = "alpha beta" ]
}

@test "is_secret_key spots secret-looking names" {
  is_secret_key TAILSCALE_AUTHKEY
  is_secret_key WIFI_PASSWORD
  run is_secret_key WIFI_CONNECTION
  [ "$status" -eq 1 ]
}
