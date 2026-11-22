# shellcheck shell=bash
# Shared test setup: a throwaway HOME, stubs for every system command, a fake root
# for files written through sudo, and fixtures for /proc/meminfo and /etc/os-release.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

beast_setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
  mkdir -p "$HOME"
  export STATE="$TMP/state" FAKEROOT="$TMP/root"
  mkdir -p "$STATE" "$FAKEROOT"
  export PATH="$REPO_ROOT/tests/stubs:$PATH"
  export NO_COLOR=1
  unset BEAST_CONFIG BEAST_NONINTERACTIVE BEAST_SUDO_READY SSH_CONNECTION TAILSCALE_AUTHKEY TS_API_TOKEN WIFI_PSK

  export BEAST_MEMINFO="$TMP/meminfo" BEAST_OS_RELEASE="$TMP/os-release"
  printf 'MemTotal:       32617068 kB\nSwapTotal:       8388604 kB\n' >"$BEAST_MEMINFO"
  printf 'ID=ubuntu\nVERSION_ID="26.04"\nPRETTY_NAME="Ubuntu 26.04.1 LTS"\n' >"$BEAST_OS_RELEASE"
}

beast_teardown() { rm -rf "$TMP"; }

beast() { bash "$REPO_ROOT/bin/beast" "$@" </dev/null; }
beast_check() { bash "$REPO_ROOT/bin/beast-check" "$@" </dev/null; }
lights() { bash "$REPO_ROOT/bin/lights" "$@"; }

# check_status ID: the status beast-check --json gives that check ("" if absent).
check_status() {
  beast_check --json | jq -r --arg id "$1" '.checks[] | select(.id == $id) | .status'
}

# validate SCHEMA: validate stdin (a JSON document, or NDJSON: one document per line).
validate() {
  python3 -c '
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
lines = [l for l in sys.stdin.read().splitlines() if l.strip()]
docs = [json.loads(l) for l in lines] if sys.argv[2] == "ndjson" else [json.loads("\n".join(lines))]
assert docs, "no output"
for d in docs:
    jsonschema.validate(d, schema)
print("valid:", len(docs))
' "$REPO_ROOT/docs/json-schema/$1" "${2:-doc}"
}

# refute CMD...: CMD must fail. (A bare `! cmd` never fails a bats test.)
refute() {
  if "$@"; then
    echo "expected to fail: $*"
    return 1
  fi
}

# bats `run` mixes stderr into $output; these pick out beast's JSON (stdout) lines.
# shellcheck disable=SC2154  # $output is set by bats' run
json_lines() { printf '%s\n' "$output" | grep '^{'; }
# shellcheck disable=SC2154
summary_line() { printf '%s\n' "$output" | grep '^{"type":"summary"'; }
