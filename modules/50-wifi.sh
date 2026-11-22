# shellcheck shell=bash disable=SC2154  # WIFI_CONNECTION comes from the config
# 50-wifi (log §6.1, §11.1): a system-wide Wi-Fi profile that isn't tied to a device
# name, no duplicate profiles, and Wi-Fi power saving off. Skipped on Ethernet.
# Profiles are always addressed by UUID. The password (WIFI_PSK or a hidden prompt)
# goes to NetworkManager on stdin, never on a command line.
# beast-check: net.wifi, wifi.ifname.<name>.

POWERSAVE_DEST=/etc/NetworkManager/conf.d/wifi-powersave-off.conf
POWERSAVE_SRC="$BEAST_ROOT/config/networkmanager/wifi-powersave-off.conf"

describe() { echo "Wi-Fi that connects at boot without a login, on any device name"; }

nm_get() { nmcli -g "$1" connection show uuid "$2" 2>/dev/null; }

wifi_uuid() {
  if [ -n "${WIFI_CONNECTION:-}" ]; then
    nmcli -g connection.uuid connection show id "$WIFI_CONNECTION" 2>/dev/null | head -n 1
  else
    nmcli -t -f UUID,TYPE connection show --active 2>/dev/null | awk -F: '$2 == "802-11-wireless" { print $1; exit }'
  fi
}

# duplicates UUID: other Wi-Fi profiles for the same SSID (never the active one).
duplicates() {
  local u=$1 ssid other type
  ssid=$(nm_get 802-11-wireless.ssid "$u")
  [ -n "$ssid" ] || return 0
  while IFS=: read -r other type; do
    if [ "$type" != 802-11-wireless ] || [ "$other" = "$u" ]; then continue; fi
    [ "$(nm_get 802-11-wireless.ssid "$other")" = "$ssid" ] && printf '%s\n' "$other"
  done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)
  return 0
}

uses_psk() {
  case $(nm_get 802-11-wireless-security.key-mgmt "$1") in wpa-psk | sae) return 0 ;; esac
  return 1
}
psk_flags() {
  local f
  f=$(nm_get 802-11-wireless-security.psk-flags "$1")
  printf '%s' "${f%% *}"
}
psk_ok() { ! uses_psk "$1" || [ "$(psk_flags "$1")" = 0 ]; }

profile_ok() {
  [ -z "$(nm_get connection.permissions "$1")" ] && psk_ok "$1" &&
    [ "$(nm_get connection.autoconnect "$1")" = yes ] &&
    [ -z "$(nm_get connection.interface-name "$1")" ]
}

check() {
  local u
  if ! have nmcli; then
    module_message "NetworkManager isn't installed"
    return "$MOD_SKIPPED"
  fi
  u=$(wifi_uuid)
  if [ -z "$u" ]; then
    module_message "no active Wi-Fi connection (Ethernet)"
    return "$MOD_SKIPPED"
  fi
  module_message "$(nm_get connection.id "$u") ($u)"
  profile_ok "$u" && [ -z "$(duplicates "$u")" ] && file_same "$POWERSAVE_SRC" "$POWERSAVE_DEST"
}

plan() {
  local u d
  u=$(wifi_uuid)
  for d in $(duplicates "$u"); do echo "delete duplicate profile uuid $d ($(nm_get connection.id "$d")), after confirmation"; done
  if uses_psk "$u" && [ "$(psk_flags "$u")" != 0 ]; then
    echo "store the Wi-Fi password system-wide (from WIFI_PSK or a hidden prompt; manual action if neither)"
  fi
  profile_ok "$u" || echo "nmcli connection modify uuid $u connection.permissions \"\" connection.autoconnect yes connection.interface-name \"\""
  if ! file_same "$POWERSAVE_SRC" "$POWERSAVE_DEST"; then
    echo "install $POWERSAVE_DEST; restart NetworkManager (drops the network for a few seconds)"
  fi
}

# set_psk UUID: returns 0 when stored, 1 when there's no password to store.
set_psk() {
  local u=$1 psk=${WIFI_PSK:-} again=''
  if [ -z "$psk" ]; then
    interactive || return 1
    info "The Wi-Fi password is stored in the desktop session, so it can't be used at boot."
    read_secret psk "Wi-Fi password for '$(nm_get connection.id "$u")'" || return 1
    read_secret again "Same password again" || return 1
    if [ -z "$psk" ] || [ "$psk" != "$again" ]; then
      err "the passwords were empty or didn't match"
      return 1
    fi
  fi
  # printf is a shell builtin: the password never becomes a process argument.
  printf 'set 802-11-wireless-security.psk-flags 0\nset 802-11-wireless-security.psk %s\nsave persistent\nquit\n' "$psk" |
    sudo nmcli connection edit uuid "$u" >/dev/null
  info "Wi-Fi password stored system-wide"
}

apply() {
  local u name dups d pending=0
  u=$(wifi_uuid)
  name=$(nm_get connection.id "$u")
  info "Wi-Fi profile: $name ($u)"

  dups=$(duplicates "$u")
  if [ -n "$dups" ]; then
    info "Inactive profiles for the same network (the active one is kept):"
    for d in $dups; do info "  $d  $(nm_get connection.id "$d")"; done
    if confirm "Delete these duplicate profiles?"; then
      for d in $dups; do run_sudo nmcli connection delete uuid "$d"; done
    else
      manual_action wifi.duplicates "Delete the duplicate Wi-Fi profiles: sudo nmcli connection delete uuid $(printf '%s' "$dups" | tr '\n' ' ')(or run beast install wifi --yes)"
      pending=1
    fi
  fi

  if uses_psk "$u" && [ "$(psk_flags "$u")" != 0 ]; then
    if ! set_psk "$u"; then
      manual_action wifi.password "The Wi-Fi password for '$name' is in the desktop session. In a terminal on beast: export WIFI_PSK (don't paste it into a chat), then run beast install wifi"
      pending=1
    fi
  fi

  # interface-name "" keeps the profile working after a device rename (log §10.3).
  run_sudo nmcli connection modify uuid "$u" connection.permissions "" connection.autoconnect yes connection.interface-name ""

  if ! file_same "$POWERSAVE_SRC" "$POWERSAVE_DEST"; then
    install_file "$POWERSAVE_SRC" "$POWERSAVE_DEST"
    restart_networkmanager
  fi
  module_message "$name: system-wide, any device name, power saving off"
  [ "$pending" = 0 ] || return "$MOD_MANUAL"
}

restart_networkmanager() {
  warn "Restarting NetworkManager drops the network (and SSH) for a few seconds."
  if interactive && ! confirm "Restart NetworkManager now?"; then
    info "Not restarting. Power saving turns off after: sudo systemctl restart NetworkManager (or a reboot)."
    return 0
  fi
  # Scheduled, so this command returns first and the restart survives an SSH drop.
  run_sudo systemd-run --on-active=5s systemctl restart NetworkManager
  info "NetworkManager restarts in 5 s. If SSH drops, reconnect in about 15 s."
}

verify() { profile_ok "$(wifi_uuid)"; }
