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

# Settings from the earlier kit version of this repo.
OLD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kit/kit.conf"

plan() {
  echo "create $BEAST_CONFIG from config/beast.conf.example"
  if [ -f "$OLD_CONFIG" ]; then echo "carry over the settings in $OLD_CONFIG"; fi
}

# old_settings: KEY=VALUE lines from the old kit config whose key beast also has.
old_settings() {
  local keys line key
  keys=$(config_keys)
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)= ]] || continue
    key=${BASH_REMATCH[1]}
    if printf '%s\n' "$keys" | grep -qx "$key"; then
      printf '%s\n' "${line#"${line%%[![:space:]]*}"}"
    else
      info "not carried over from $OLD_CONFIG: $key (beast has no such setting)"
    fi
  done <"$OLD_CONFIG"
}

apply() {
  local tmp line key old
  session_message
  mkdir -p "$(dirname "$BEAST_CONFIG")"
  if [ ! -f "$OLD_CONFIG" ]; then
    cp "$BEAST_ROOT/config/beast.conf.example" "$BEAST_CONFIG"
    info "created $BEAST_CONFIG (defaults match beast; edit it to change them)"
    return 0
  fi
  old=$(old_settings)
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ ^([A-Z][A-Z0-9_]*)= ]] && printf '%s\n' "$old" | grep -q "^${BASH_REMATCH[1]}="; then
      key=${BASH_REMATCH[1]}
      printf '%s\n' "$old" | grep "^$key=" | tail -n 1
    else
      printf '%s\n' "$line"
    fi
  done <"$BEAST_ROOT/config/beast.conf.example" >"$tmp"
  mv "$tmp" "$BEAST_CONFIG"
  info "created $BEAST_CONFIG with your settings from $OLD_CONFIG"
}

verify() { [ -f "$BEAST_CONFIG" ]; }
