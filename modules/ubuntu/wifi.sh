# shellcheck shell=bash disable=SC2154  # WIFI_CONNECTION comes from host.conf
# wifi (SETUP-LOG §6.1): make the Wi-Fi profile connect without a desktop login,
# and turn off Wi-Fi power saving.
#
# Secrets (SPEC §8.4): if the password lived in the desktop keyring, it's asked
# for without echo and handed to NetworkManager on stdin (`nmcli connection edit`),
# never as a command-line argument, so it can't show up in `ps` or sudo's log.

POWERSAVE_CONF=/etc/NetworkManager/conf.d/wifi-powersave-off.conf

describe() { echo "Wi-Fi that connects at boot without a login; power saving off"; }

# Unescape nmcli terse output (\: and \\).
_nm_unescape() { sed 's/\\:/:/g; s/\\\\/\\/g'; }

wifi_connection() {
  if [ -n "${WIFI_CONNECTION:-}" ]; then
    printf '%s\n' "$WIFI_CONNECTION"
    return 0
  fi
  nmcli -t -f TYPE,NAME connection show --active 2>/dev/null |
    sed -n 's/^802-11-wireless://p' | head -n 1 | _nm_unescape
}

applies() {
  local c
  if ! have nmcli; then
    echo "NetworkManager isn't installed"
    return 1
  fi
  c=$(wifi_connection)
  if [ -z "$c" ]; then
    echo "no active Wi-Fi connection (Ethernet?)"
    return 1
  fi
  if ! nmcli -g connection.id connection show "$c" >/dev/null 2>&1; then
    echo "Wi-Fi connection '$c' not found (check WIFI_CONNECTION)"
    return 1
  fi
}

nm_get() { nmcli -g "$1" connection show "$2" 2>/dev/null; }

psk_flags() {
  local f
  f=$(nm_get 802-11-wireless-security.psk-flags "$1")
  printf '%s\n' "${f%% *}" # "0 (none)" → "0"
}

# uses_psk CONNECTION: WPA/WPA3 personal (has a password); open networks don't.
uses_psk() {
  case $(nm_get 802-11-wireless-security.key-mgmt "$1") in wpa-psk | sae) return 0 ;; esac
  return 1
}

psk_ok() { ! uses_psk "$1" || [ "$(psk_flags "$1")" = 0 ]; }

profile_ok() {
  [ -z "$(nm_get connection.permissions "$1")" ] &&
    psk_ok "$1" &&
    [ "$(nm_get connection.autoconnect "$1")" = yes ]
}

check() {
  local c
  c=$(wifi_connection)
  profile_ok "$c" && file_same "$(host_file networkmanager/wifi-powersave-off.conf)" "$POWERSAVE_CONF"
}

# set_psk CONNECTION: ask for the password and store it system-wide.
set_psk() {
  local c=$1 psk='' psk2=''
  if [ "$KIT_DRY_RUN" = 1 ]; then
    info "would ask for the Wi-Fi password (hidden) and store it with nmcli connection edit (not shown)"
    return 0
  fi
  if ! has_tty; then
    err "The Wi-Fi password is stored in the desktop session, and there's no terminal to ask for it."
    return "$KIT_BLOCKED"
  fi
  info "The password for '$c' is stored in your desktop session, so it can't be used at boot."
  read_secret psk "Wi-Fi password for '$c'" || return "$KIT_BLOCKED"
  read_secret psk2 "Same password again" || return "$KIT_BLOCKED"
  if [ "$psk" != "$psk2" ] || [ -z "$psk" ]; then
    unset psk psk2
    err "The passwords didn't match (or were empty)."
    return 1
  fi
  unset psk2
  # Flags and password are saved together, so the profile never expects a stored
  # password it doesn't have. stdin, not argv: printf is a shell builtin, so the
  # password never becomes a process argument.
  printf 'set 802-11-wireless-security.psk-flags 0\nset 802-11-wireless-security.psk %s\nsave persistent\nquit\n' "$psk" |
    sudo nmcli connection edit id "$c" >/dev/null
  unset psk
  ok "Password stored system-wide for '$c'"
}

apply() {
  local c flags rc=0
  c=$(wifi_connection)
  info "Wi-Fi connection: $c"
  flags=$(psk_flags "$c")

  # Password first: if it can't be stored, nothing else changes.
  if uses_psk "$c" && [ "$flags" != 0 ]; then
    set_psk "$c" || rc=$?
    [ "$rc" = 0 ] || return "$rc"
  fi
  run_sudo nmcli connection modify "$c" connection.permissions "" connection.autoconnect yes

  if ! file_same "$(host_file networkmanager/wifi-powersave-off.conf)" "$POWERSAVE_CONF"; then
    install_file "$(host_file networkmanager/wifi-powersave-off.conf)" "$POWERSAVE_CONF"
    restart_networkmanager
  fi
}

restart_networkmanager() {
  if [ "$KIT_DRY_RUN" = 1 ]; then
    info "would ask, then restart NetworkManager in the background"
    return 0
  fi
  warn "Restarting NetworkManager drops the network for a few seconds${KIT_SESSION:+ (this is a $KIT_SESSION session)}."
  if ! confirm_always "Restart NetworkManager now?"; then
    info "Not restarting. Power saving turns off after: sudo systemctl restart NetworkManager (or a reboot)."
    return 0
  fi
  # Detached, so the restart completes even if this SSH session drops.
  run_sudo systemd-run --quiet --collect --unit="kit-nm-restart-$(timestamp)" --on-active=3 \
    systemctl restart NetworkManager
  info "NetworkManager restarts in 3 s. If your SSH session drops, reconnect in ~15 s."
}

verify() {
  local c perms flags auto
  c=$(wifi_connection)
  perms=$(nm_get connection.permissions "$c")
  flags=$(psk_flags "$c")
  auto=$(nm_get connection.autoconnect "$c")
  if [ -z "$perms" ] && psk_ok "$c" && [ "$auto" = yes ]; then
    report ok "Wi-Fi '$c': system-wide, password stored, autoconnect"
  else
    report fail "Wi-Fi '$c': permissions='${perms}' psk-flags=${flags:-?} autoconnect=${auto:-?}" "kit install wifi"
  fi
  if file_same "$(host_file networkmanager/wifi-powersave-off.conf)" "$POWERSAVE_CONF"; then
    report ok "Wi-Fi power saving off"
  else
    report fail "Wi-Fi power saving config missing" "kit install wifi"
  fi
  report_status
}
