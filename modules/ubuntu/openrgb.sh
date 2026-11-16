# shellcheck shell=bash disable=SC2154  # OPENRGB_* come from host.conf
# openrgb (SETUP-LOG §8.2–8.3): SMBus access and the pinned OpenRGB AppImage.
# Ubuntu's openrgb package is too old for the MSI controller, so it's removed.

I2C_CONF=/etc/modules-load.d/i2c.conf
UDEV_RULES=/etc/udev/rules.d/60-openrgb.rules

describe() { echo "OpenRGB ${OPENRGB_VERSION:-} (pinned AppImage, SMBus, udev rules)"; }

binary_ok() { [ -x "$OPENRGB_BIN" ] && [ "$(sha256_of "$OPENRGB_BIN")" = "$OPENRGB_SHA256" ]; }

check() {
  file_same "$(host_file modules-load/i2c.conf)" "$I2C_CONF" &&
    apt_installed libfuse2t64 libopengl0 &&
    ! apt_installed openrgb &&
    binary_ok &&
    [ -f "$UDEV_RULES" ]
}

download_binary() {
  local tmp
  case $OPENRGB_URL in https://*) ;; *)
    err "OPENRGB_URL must be https://"
    return 1
    ;;
  esac
  if [ "$KIT_DRY_RUN" = 1 ]; then
    run_cmd curl -fL --proto '=https' --tlsv1.2 -o /tmp/openrgb.AppImage "$OPENRGB_URL"
    info "would check SHA-256 $OPENRGB_SHA256"
    run_sudo install -m 755 /tmp/openrgb.AppImage "$OPENRGB_BIN"
    return 0
  fi
  tmp=$(mktemp -d)
  info "Downloading OpenRGB $OPENRGB_VERSION"
  if ! curl -fL --proto '=https' --tlsv1.2 --progress-bar -o "$tmp/openrgb.AppImage" "$OPENRGB_URL"; then
    rm -rf "$tmp"
    err "Download failed: $OPENRGB_URL"
    return 1
  fi
  if [ "$(sha256_of "$tmp/openrgb.AppImage")" != "$OPENRGB_SHA256" ]; then
    rm -rf "$tmp"
    err "Checksum mismatch for $OPENRGB_URL. Not installing it."
    return 1
  fi
  ok "Checksum verified"
  run_sudo install -m 755 "$tmp/openrgb.AppImage" "$OPENRGB_BIN"
  rm -rf "$tmp"
}

apply() {
  install_file "$(host_file modules-load/i2c.conf)" "$I2C_CONF"
  # -a is required: without it, only the first module name is loaded.
  run_sudo modprobe -a i2c-dev i2c-i801

  apt_install libfuse2t64 libopengl0
  if apt_installed openrgb; then
    info "Removing Ubuntu's openrgb package (too old for the MSI controller)"
    run_sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y openrgb
  fi

  local new_binary=0
  if ! binary_ok; then
    download_binary
    new_binary=1
  fi
  if [ "$new_binary" = 1 ] || [ ! -f "$UDEV_RULES" ]; then
    run_sudo "$OPENRGB_BIN" --generate-udev-rules "$UDEV_RULES"
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
  fi
}

uninstall() {
  run_sudo rm -f "$OPENRGB_BIN" "$UDEV_RULES" "$I2C_CONF"
  run_sudo udevadm control --reload-rules
  info "Removed OpenRGB, its udev rules and $I2C_CONF (the i2c modules stay loaded until reboot)."
}

verify() {
  local list name
  if binary_ok; then
    report ok "OpenRGB $OPENRGB_VERSION installed (checksum ok)"
  elif [ -x "$OPENRGB_BIN" ]; then
    report fail "OpenRGB at $OPENRGB_BIN doesn't match the pinned checksum" "kit install openrgb"
  else
    report fail "OpenRGB not installed" "kit install openrgb"
  fi
  if lsmod 2>/dev/null | grep -q '^i2c_dev'; then
    report ok "i2c-dev loaded"
  else
    report fail "i2c-dev not loaded" "sudo modprobe -a i2c-dev i2c-i801"
  fi
  if [ -f "$UDEV_RULES" ]; then
    report ok "udev rules installed"
  else
    report fail "udev rules missing" "kit install openrgb"
  fi
  if [ -x "$OPENRGB_BIN" ]; then
    list=$("$OPENRGB_BIN" --noautoconnect -l 2>/dev/null || true)
    for name in ${LIGHTS_RAM_DEVICES:+"$LIGHTS_RAM_DEVICES"} ${LIGHTS_GPU_DEVICE:+"$LIGHTS_GPU_DEVICE"} ${LIGHTS_MB_DEVICE:+"$LIGHTS_MB_DEVICE"}; do
      if printf '%s\n' "$list" | grep -q -- "$name"; then
        report ok "Device found: $name"
      else
        report fail "Device not found: $name" "check the i2c modules and udev rules, then: kit lights status"
      fi
    done
  fi
  report_status
}
