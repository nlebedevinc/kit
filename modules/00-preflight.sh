# shellcheck shell=bash
# 00-preflight (SPEC §5): refuses root, checks sudo, takes the lock (those three run
# in bin/beast's own process, see preflight()), detects the OS, SSH session and TTY,
# and creates the config file.

describe() { echo "Checks the OS, session and sudo; creates the config file"; }

session_message() {
  local id ver where how
  id=$(os_release_value ID)
  ver=$(os_release_value VERSION_ID)
  if is_ssh_session; then where="over SSH"; else where="local"; fi
  if interactive; then how="interactive"; else how="non-interactive"; fi
  module_message "${id:-unknown} ${ver:-?}, $where, $how; config $BEAST_CONFIG"
}

check() {
  session_message
  [ -f "$BEAST_CONFIG" ]
}

plan() {
  echo "create $BEAST_CONFIG from config/beast.conf.example"
}

apply() {
  session_message
  mkdir -p "$(dirname "$BEAST_CONFIG")"
  cp "$BEAST_ROOT/config/beast.conf.example" "$BEAST_CONFIG"
  info "created $BEAST_CONFIG (defaults match beast; edit it to change them)"
}

verify() { [ -f "$BEAST_CONFIG" ]; }
