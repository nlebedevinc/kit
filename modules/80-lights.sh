# shellcheck shell=bash disable=SC2154  # LIGHTS_BOOT comes from the config
# 80-lights (log §8.4–8.6): the lights command and the boot service that turns the
# lights off. With LIGHTS_BOOT=hardware the service stays disabled, so the
# motherboard's stored rainbow survives (log §8.6). beast-check: lights.boot.

LIGHTS_DEST=/usr/local/bin/lights
UNIT=lights-off.service
UNIT_DEST=/etc/systemd/system/$UNIT
# The service runs as root at boot; this tells lights where the user's config is.
DROPIN_DEST=/etc/systemd/system/$UNIT.d/config.conf

describe() { echo "The lights command; lights off at boot (LIGHTS_BOOT=off)"; }

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
  files_ok && boot_ok
}

plan() {
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
}

verify() { boot_ok; }

uninstall() {
  run_sudo systemctl disable "$UNIT" || true
  run_sudo rm -f "$UNIT_DEST" "$DROPIN_DEST" "$LIGHTS_DEST"
  run_sudo rm -rf "${DROPIN_DEST%/*}"
  run_sudo systemctl daemon-reload
}
