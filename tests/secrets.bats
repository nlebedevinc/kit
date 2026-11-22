#!/usr/bin/env bats
# The repository must never contain secrets or personal contact details.
# shellcheck disable=SC2143  # [ -z "$(… | grep …)" ] reads clearly here

load helpers

tracked_files() {
  (cd "$REPO_ROOT" && find . -type f -not -path './.git/*' -not -name 'secrets.bats' | sort)
}

grep_repo() { (cd "$REPO_ROOT" && tracked_files | xargs grep -nIE "$1" 2>/dev/null) || true; }

@test "no Tailscale auth keys (test fixtures use TESTONLY)" {
  run grep_repo 'tskey-[A-Za-z0-9-]{8,}'
  [ -z "$(printf '%s\n' "$output" | grep -v TESTONLY)" ]
}

@test "no private keys" {
  run grep_repo 'BEGIN [A-Z ]*PRIVATE KEY'
  [ -z "$output" ]
}

@test "no email addresses except example.com, noreply and openssh.com" {
  run grep_repo '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}'
  [ -z "$(printf '%s\n' "$output" | grep -oE '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}' |
    grep -vE '@example\.com$|^noreply@|@openssh\.com$')" ]
}

@test "the email check really catches an address" {
  printf 'contact: someone@gmail.com\n' | grep -qE '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}'
}

@test "no Wi-Fi passwords in config files (test fixtures use TESTONLY)" {
  run grep_repo '^[[:space:]]*(WIFI_PASSWORD|WIFI_PSK|wifi-sec\.psk)[[:space:]]*=[[:space:]]*[^"[:space:]]'
  [ -z "$(printf '%s\n' "$output" | grep -v TESTONLY)" ]
}
