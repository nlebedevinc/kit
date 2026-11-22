# shellcheck shell=bash disable=SC2154  # LIGHTS_BOOT comes from the config
# 80-lights (log §8.4–8.6): the lights command and the boot service that turns the
# lights off. With LIGHTS_BOOT=hardware the service stays disabled, so the
# motherboard's stored rainbow survives (log §8.6). beast-check: lights.boot.

LIGHTS_DEST=/usr/local/bin/lights
UNIT=lights-off.service
UNIT_DEST=/etc/systemd/system/$UNIT
# The service runs as root at boot; this tells lights where the user's config is.
DROPIN_DEST=/etc/systemd/system/$UNIT.d/config.conf

# The earlier kit version of this repo installed the same thing under other names.
KIT_BIN=/usr/local/bin/kit-lights
KIT_UNIT=kit-lights-off.service
KIT_UNIT_DEST=/etc/systemd/system/$KIT_UNIT
KIT_CONF=/etc/kit/lights.conf

describe() { echo "The lights command; lights off at boot (LIGHTS_BOOT=off)"; }

boot_setting_ok() { [ "$LIGHTS_BOOT" = off ] || [ "$LIGHTS_BOOT" = hardware ]; }
kit_setup_present() { [ -e "$KIT_BIN" ] || [ -e "$KIT_UNIT_DEST" ] || [ -e "$KIT_CONF" ]; }

# remove_kit_setup: returns 1 if it's still there (not confirmed).
remove_kit_setup() {
  kit_setup_present || return 0
  info "Found the lights setup from the kit version: $KIT_BIN, $KIT_UNIT_DEST, $KIT_CONF"
  if ! confirm "Remove it (it's replaced by $LIGHTS_DEST and $UNIT)?"; then
    manual_action lights.kit_setup "Remove the old kit lights setup, or run beast install lights --yes: sudo systemctl disable $KIT_UNIT; sudo rm -f $KIT_BIN $KIT_UNIT_DEST $KIT_CONF"
    return 1
  fi
  run_sudo systemctl disable "$KIT_UNIT" || true
  run_sudo rm -f "$KIT_BIN" "$KIT_UNIT_DEST" "$KIT_CONF"
  if [ -d "${KIT_CONF%/*}" ]; then run_sudo rmdir --ignore-fail-on-non-empty "${KIT_CONF%/*}"; fi
}

dropin() { printf '[Service]\nEnvironment="BEAST_CONFIG=%s"\n' "$BEAST_CONFIG"; }

boot_ok() {
  local state
  state=$(systemctl is-enabled "$UNIT" 2>/dev/null)
  if [ "$LIGHTS_BOOT" = hardware ]; then [ "$state" != enabled ]; else [ "$state" = enabled ]; fi
}

files_ok() {
  file_same "$BEAST_ROOT/bin/lights" "$LIGHTS_DEST" &&
    file_same "$BEAST_ROOT/config/systemd/$UNIT" "$UNIT_DEST" &&
    dropin | same_content "$DROPIN_DEST"
}

check() {
  if ! rgb_hardware; then
    module_message "no supported RGB hardware"
    return "$MOD_SKIPPED"
  fi
  boot_setting_ok && files_ok && boot_ok && ! kit_setup_present
}

plan() {
  boot_setting_ok || echo "stop: LIGHTS_BOOT must be off or hardware (it's '$LIGHTS_BOOT')"
  if kit_setup_present; then echo "remove the kit lights setup ($KIT_BIN, $KIT_UNIT, $KIT_CONF), after confirmation"; fi
  file_same "$BEAST_ROOT/bin/lights" "$LIGHTS_DEST" || echo "install bin/lights to $LIGHTS_DEST"
  file_same "$BEAST_ROOT/config/systemd/$UNIT" "$UNIT_DEST" || echo "install $UNIT_DEST"
  dropin | same_content "$DROPIN_DEST" || echo "install $DROPIN_DEST (BEAST_CONFIG for the boot service)"
  if [ "$LIGHTS_BOOT" = hardware ]; then
    boot_ok || echo "systemctl disable $UNIT (LIGHTS_BOOT=hardware)"
  else
    boot_ok || echo "systemctl enable $UNIT"
  fi
}

apply() {
  local pending=0
  if ! boot_setting_ok; then
    err "LIGHTS_BOOT must be off or hardware (it's '$LIGHTS_BOOT')"
    return 1
  fi
  remove_kit_setup || pending=1
  install_file "$BEAST_ROOT/bin/lights" "$LIGHTS_DEST" 755
  install_file "$BEAST_ROOT/config/systemd/$UNIT" "$UNIT_DEST"
  dropin | render_file "$DROPIN_DEST"
  run_sudo systemctl daemon-reload
  if [ "$LIGHTS_BOOT" = hardware ]; then
    boot_ok || run_sudo systemctl disable "$UNIT"
    module_message "boot service disabled (LIGHTS_BOOT=hardware); the stored rainbow returns after a full power cycle"
  else
    boot_ok || run_sudo systemctl enable "$UNIT"
    module_message "lights go off at every boot"
  fi
  [ "$pending" = 0 ] || return "$MOD_MANUAL"
}

verify() { boot_ok; }

uninstall() {
  run_sudo systemctl disable "$UNIT" || true
  run_sudo rm -f "$UNIT_DEST" "$DROPIN_DEST" "$LIGHTS_DEST"
  run_sudo rm -rf "${DROPIN_DEST%/*}"
  run_sudo systemctl daemon-reload
}
