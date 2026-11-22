# shellcheck shell=bash disable=SC2154  # OPENRGB_* come from the config
# 70-openrgb (log §8.2–8.3): SMBus access and the pinned OpenRGB AppImage (SHA-256).
# Ubuntu's openrgb package is too old for the MSI controller, so it's removed.
# Skipped when there's no supported RGB hardware.

I2C_DEST=/etc/modules-load.d/i2c.conf
I2C_SRC="$BEAST_ROOT/config/modules-load/i2c.conf"
UDEV_RULES=/etc/udev/rules.d/60-openrgb.rules

describe() { echo "OpenRGB ${OPENRGB_VERSION} (pinned AppImage), SMBus access, udev rules"; }

binary_ok() { [ -x "$OPENRGB_BIN" ] && [ "$(sha256_of "$OPENRGB_BIN")" = "$OPENRGB_SHA256" ]; }

check() {
  if ! rgb_hardware; then
    module_message "no supported RGB hardware (MSI MYSTIC LIGHT, USB 0db0:0076)"
    return "$MOD_SKIPPED"
  fi
  file_same "$I2C_SRC" "$I2C_DEST" && apt_installed libfuse2t64 libopengl0 &&
    ! apt_installed openrgb && binary_ok && [ -f "$UDEV_RULES" ]
}

plan() {
  file_same "$I2C_SRC" "$I2C_DEST" || echo "install $I2C_DEST"
  echo "modprobe -a i2c-dev i2c-i801"
  apt_installed libfuse2t64 libopengl0 || echo "apt-get install -y libfuse2t64 libopengl0"
  ! apt_installed openrgb || echo "apt-get remove -y openrgb (too old for the MSI controller)"
  binary_ok || echo "download $OPENRGB_URL, check SHA-256 $OPENRGB_SHA256, install as $OPENRGB_BIN"
  [ -f "$UDEV_RULES" ] || echo "openrgb --generate-udev-rules $UDEV_RULES; udevadm control --reload-rules; udevadm trigger"
}

download() {
  local tmp
  case $OPENRGB_URL in https://*) ;; *)
    err "OPENRGB_URL must be https://"
    return 1
    ;;
  esac
  tmp=$(mktemp -d)
  info "Downloading OpenRGB $OPENRGB_VERSION"
  if ! curl -fL --proto '=https' --max-time 600 -sS -o "$tmp/openrgb.AppImage" "$OPENRGB_URL"; then
    rm -rf "$tmp"
    err "download failed: $OPENRGB_URL"
    return 1
  fi
  if [ "$(sha256_of "$tmp/openrgb.AppImage")" != "$OPENRGB_SHA256" ]; then
    rm -rf "$tmp"
    err "checksum mismatch for $OPENRGB_URL; not installing it"
    return 1
  fi
  info "checksum verified"
  run_sudo install -m 755 "$tmp/openrgb.AppImage" "$OPENRGB_BIN"
  rm -rf "$tmp"
}

apply() {
  local new=0
  install_file "$I2C_SRC" "$I2C_DEST"
  # -a is required: without it only the first module name is loaded (log §8.2).
  run_sudo modprobe -a i2c-dev i2c-i801
  apt_installed libfuse2t64 libopengl0 || apt_get install libfuse2t64 libopengl0
  if apt_installed openrgb; then apt_get remove openrgb; fi
  if ! binary_ok; then
    download
    new=1
  fi
  if [ "$new" = 1 ] || [ ! -f "$UDEV_RULES" ]; then
    run_sudo "$OPENRGB_BIN" --generate-udev-rules "$UDEV_RULES"
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
  fi
  module_message "OpenRGB $OPENRGB_VERSION at $OPENRGB_BIN"
}

verify() { binary_ok && [ -f "$UDEV_RULES" ]; }

uninstall() {
  run_sudo rm -f "$OPENRGB_BIN" "$UDEV_RULES" "$I2C_DEST"
  run_sudo udevadm control --reload-rules
}
