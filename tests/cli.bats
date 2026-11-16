#!/usr/bin/env bats
# bin/kit: commands, exit codes, the install flow and idempotency.

load helpers

setup() {
  kit_setup
  make_module alpha
  make_module beta
}
teardown() { kit_teardown; }

@test "no arguments prints help" {
  run kit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: kit"* ]]
}

@test "help for a command" {
  run kit install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"kit install [module...]"* ]]
}

@test "unknown flag and unknown command are usage errors (exit 2)" {
  run kit --bogus
  [ "$status" -eq 2 ]
  run kit --host testbox frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown command 'frobnicate'"* ]]
}

@test "no matching host is a usage error" {
  run kit list
  [ "$status" -eq 2 ]
  [[ "$output" == *"--host"* ]]
}

@test "hosts marks the active profile" {
  run kit --host testbox hosts
  [ "$status" -eq 0 ]
  [[ "$output" == *"* testbox"* ]]
}

@test "install applies modules, then a second run reports everything already done" {
  run kit --host testbox install
  [ "$status" -eq 0 ]
  [ -f "$STATE/alpha" ] && [ -f "$STATE/beta" ]
  [[ "$output" == *"0 already done, 2 applied"* ]]

  run kit --host testbox install
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 already done, 0 applied"* ]]
}

@test "install with module names runs only those" {
  run kit --host testbox install beta
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/alpha" ]
  [ -f "$STATE/beta" ]
}

@test "flags work after the command too" {
  run kit install --host testbox --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]]
}

@test "install of an unknown module is a usage error and runs nothing" {
  run kit --host testbox install alpha nope
  [ "$status" -eq 2 ]
  [ ! -e "$STATE/alpha" ]
}

@test "--dry-run changes nothing" {
  run kit --host testbox --dry-run install
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] touch"* ]]
  [ ! -e "$STATE/alpha" ]
  [[ "$output" == *"2 would apply"* ]]
}

@test "modules that don't apply are skipped with their reason" {
  make_module gamma 'describe() { echo Gamma; }
applies() { echo "no such hardware"; return 1; }
check() { return 1; }
apply() { touch "$STATE/gamma"; }'
  run kit --host testbox install gamma
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped: no such hardware"* ]]
  [ ! -e "$STATE/gamma" ]
}

@test "a failing module fails the run (exit 1) but later modules still run" {
  make_module broken 'describe() { echo Broken; }
check() { return 1; }
apply() { false; touch "$STATE/after-false"; }'
  run kit --host testbox install broken alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: broken"* ]]
  # set -e stops the module at the first error
  [ ! -e "$STATE/after-false" ]
  [ -f "$STATE/alpha" ]
}

@test "a blocked module exits 3" {
  make_module gated 'describe() { echo Gated; }
check() { return 1; }
apply() { err "no key yet"; return "$KIT_BLOCKED"; }'
  run kit --host testbox install gated
  [ "$status" -eq 3 ]
  [[ "$output" == *"blocked: gated"* ]]
}

@test "apply that succeeds but fails verify is reported as failed" {
  make_module liar 'describe() { echo Liar; }
check() { return 1; }
apply() { :; }'
  run kit --host testbox install liar
  [ "$status" -eq 1 ]
  [[ "$output" == *"verification failed"* ]]
}

@test "list shows applied, not applied and skipped modules" {
  make_module gamma 'describe() { echo Gamma; }
applies() { echo "no GPU"; return 1; }
check() { return 1; }
apply() { :; }'
  make_host testbox 'KIT_MODULES="alpha beta gamma"'
  touch "$STATE/alpha"
  run kit --host testbox list
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ alpha"* ]]
  [[ "$output" == *"⬜ beta"* ]]
  [[ "$output" == *"gamma"*"(no GPU)"* ]]
}

@test "doctor fails until everything is applied, then passes" {
  run kit --host testbox doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ Module alpha"* ]]
  kit --host testbox install >/dev/null
  run kit --host testbox doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"All checks passed"* ]]
}

@test "uninstall without module support fails clearly" {
  run kit --host testbox uninstall alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't be uninstalled"* ]]
}

@test "config prints values and hides secrets" {
  make_host testbox 'KIT_MODULES="alpha beta"
WIFI_PASSWORD=TESTONLY-hunter2'
  run kit --host testbox config
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREETING=hello"* ]]
  [[ "$output" == *"WIFI_PASSWORD=<hidden>"* ]]
  [[ "$output" != *"TESTONLY-hunter2"* ]]
}

@test "host commands get their arguments untouched" {
  printf '%s\n' 'printf "args:"; printf " [%s]" "$@"; printf "\n"' >"$ROOT/hosts/testbox/commands/echoargs"
  run kit --host testbox echoargs off --help "two words"
  [ "$status" -eq 0 ]
  [ "$output" = "args: [off] [--help] [two words]" ]
}

@test "commands with no arguments work under set -u (bash 3.2 empty arrays)" {
  run kit --host testbox list
  [ "$status" -eq 0 ]
}
