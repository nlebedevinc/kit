# shellcheck shell=bash disable=SC2154  # LIGHTS_*/OPENRGB_BIN come from host.conf
# lights (SETUP-LOG §8.4–8.6): kit-lights command + boot service.
# LIGHTS_BOOT=off → the service turns the lights off at boot.
# LIGHTS_BOOT=hardware → service disabled, so the motherboard's stored rainbow survives.

LIGHTS_BIN=/usr/local/bin/kit-lights
LIGHTS_CONF=/etc/kit/lights.conf
UNIT=kit-lights-off.service
UNIT_FILE=/etc/systemd/system/$UNIT
OLD_BIN=/usr/local/bin/lights
OLD_UNIT=lights-off.service
OLD_UNIT_FILE=/etc/systemd/system/$OLD_UNIT

describe() { echo "kit lights command and boot service (LIGHTS_BOOT=${LIGHTS_BOOT:-off})"; }

lights_conf() {
  local key
  echo "# Written by kit install lights. Change ~/.config/kit/kit.conf instead, then re-run it."
  for key in OPENRGB_BIN LIGHTS_BOOT LIGHTS_RAM_DEVICES LIGHTS_GPU_DEVICE LIGHTS_MB_DEVICE \
    LIGHTS_MB_ZONES LIGHTS_MB_ZONE_SIZE LIGHTS_ON_RAM_MODE LIGHTS_ON_COLOR; do
    printf '%s=%q\n' "$key" "${!key-}"
  done
}

conf_same() {
  local tmp rc=0
  tmp=$(mktemp)
  lights_conf >"$tmp"
  file_same "$tmp" "$LIGHTS_CONF" || rc=1
  rm -f "$tmp"
  return "$rc"
}

want_enabled() { [ "${LIGHTS_BOOT:-off}" = off ]; }

unit_state_ok() {
  local state
  state=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
  if want_enabled; then [ "$state" = enabled ]; else [ "$state" != enabled ]; fi
}

old_setup_present() { [ -e "$OLD_BIN" ] || [ -e "$OLD_UNIT_FILE" ]; }

check() {
  case ${LIGHTS_BOOT:-off} in off | hardware) ;; *) return 1 ;; esac
  conf_same &&
    file_same "$KIT_HOST_DIR/commands/lights" "$LIGHTS_BIN" &&
    file_same "$(host_file systemd/$UNIT)" "$UNIT_FILE" &&
    unit_state_ok &&
    ! old_setup_present
}

remove_old_setup() {
  old_setup_present || return 0
  info "Found the hand-made setup from the setup log ($OLD_BIN, $OLD_UNIT)."
  if ! confirm "Replace it with kit-lights (removes $OLD_BIN and $OLD_UNIT)?" y; then
    warn "Keeping the old setup. If both boot services are enabled, both run."
    return 0
  fi
  if systemctl is-enabled "$OLD_UNIT" >/dev/null 2>&1; then
    run_sudo systemctl disable "$OLD_UNIT"
  fi
  run_sudo rm -f "$OLD_UNIT_FILE" "$OLD_BIN"
}

apply() {
  case ${LIGHTS_BOOT:-off} in off | hardware) ;; *)
    err "LIGHTS_BOOT must be off or hardware (it's '$LIGHTS_BOOT')"
    return 1
    ;;
  esac
  remove_old_setup

  lights_conf | write_file "$LIGHTS_CONF" 644
  install_file "$KIT_HOST_DIR/commands/lights" "$LIGHTS_BIN" 755
  install_file "$(host_file systemd/$UNIT)" "$UNIT_FILE" 644
  run_sudo systemctl daemon-reload

  if want_enabled; then
    run_sudo systemctl enable "$UNIT"
    info "Lights turn off at every boot. Try it now: kit lights off"
  else
    if systemctl is-enabled "$UNIT" >/dev/null 2>&1; then run_sudo systemctl disable "$UNIT"; fi
    info "Boot service disabled; the motherboard keeps its own effect after a full power cycle (PSU off ~30 s)."
  fi
}

uninstall() {
  if systemctl is-enabled "$UNIT" >/dev/null 2>&1; then run_sudo systemctl disable "$UNIT"; fi
  run_sudo rm -f "$UNIT_FILE" "$LIGHTS_BIN" "$LIGHTS_CONF"
  run_sudo systemctl daemon-reload
  info "Removed kit-lights, its config and the boot service."
}

verify() {
  local state
  if [ -x "$LIGHTS_BIN" ] && file_same "$KIT_HOST_DIR/commands/lights" "$LIGHTS_BIN"; then
    report ok "kit-lights installed"
  else
    report fail "kit-lights missing or out of date" "kit install lights"
  fi
  if conf_same; then
    report ok "Lights config up to date ($LIGHTS_CONF)"
  else
    report fail "Lights config out of date" "kit install lights"
  fi
  state=$(systemctl is-enabled "$UNIT" 2>/dev/null || echo missing)
  if unit_state_ok; then
    report ok "Boot service $UNIT: $state (LIGHTS_BOOT=${LIGHTS_BOOT:-off})"
  else
    report fail "Boot service $UNIT: $state, but LIGHTS_BOOT=${LIGHTS_BOOT:-off}" "kit install lights"
  fi
  if old_setup_present; then
    report fail "Old hand-made lights setup still present ($OLD_BIN / $OLD_UNIT)" "kit install lights"
  fi
  report_status
}
