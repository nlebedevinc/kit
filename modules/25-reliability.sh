# shellcheck shell=bash disable=SC2154  # WATCHDOG_*, PANIC_REBOOT_SEC come from the config
# 25-reliability (log §11.2–11.3): hardware watchdog, reboot on kernel panic, smartd.
# No reboot needed. beast-check: watchdog, panic.reboot, nvme.smart.

WATCHDOG_DEST=/etc/systemd/system.conf.d/watchdog.conf
PANIC_DEST=/etc/sysctl.d/99-panic-reboot.conf

describe() { echo "Hardware watchdog, reboot on kernel panic, SSD health monitoring"; }

watchdog_conf() {
  sed -e "s/^RuntimeWatchdogSec=.*/RuntimeWatchdogSec=${WATCHDOG_SEC}s/" \
    -e "s/^RebootWatchdogSec=.*/RebootWatchdogSec=${WATCHDOG_REBOOT}/" \
    "$BEAST_ROOT/config/systemd/watchdog.conf"
}

panic_conf() {
  sed "s/^kernel.panic = .*/kernel.panic = ${PANIC_REBOOT_SEC}/" "$BEAST_ROOT/config/sysctl/99-panic-reboot.conf"
}

watchdog_on() {
  case $(systemctl show -p RuntimeWatchdogUSec --value 2>/dev/null) in
    0 | infinity | "") return 1 ;;
  esac
}
panic_on() { [ "$(sysctl -n kernel.panic 2>/dev/null || echo 0)" -gt 0 ]; }
smartd_on() { [ "$(systemctl is-enabled smartmontools 2>/dev/null)" = enabled ]; }

check() {
  watchdog_on && panic_on && smartd_on &&
    watchdog_conf | same_content "$WATCHDOG_DEST" &&
    panic_conf | same_content "$PANIC_DEST"
}

plan() {
  apt_installed smartmontools || echo "apt-get install -y smartmontools"
  watchdog_conf | same_content "$WATCHDOG_DEST" ||
    echo "write $WATCHDOG_DEST (RuntimeWatchdogSec=${WATCHDOG_SEC}s, RebootWatchdogSec=${WATCHDOG_REBOOT}); systemctl daemon-reexec"
  panic_conf | same_content "$PANIC_DEST" ||
    echo "write $PANIC_DEST (kernel.panic = ${PANIC_REBOOT_SEC}); sysctl --system"
  smartd_on || echo "systemctl enable --now smartmontools"
}

apply() {
  apt_installed smartmontools || apt_get install smartmontools
  if ! watchdog_conf | same_content "$WATCHDOG_DEST" || ! watchdog_on; then
    watchdog_conf | render_file "$WATCHDOG_DEST"
    run_sudo systemctl daemon-reexec
  fi
  if ! panic_conf | same_content "$PANIC_DEST" || ! panic_on; then
    panic_conf | render_file "$PANIC_DEST"
    run_sudo sysctl --system >/dev/null
  fi
  smartd_on || run_sudo systemctl enable --now smartmontools
  module_message "watchdog ${WATCHDOG_SEC}s, panic reboot after ${PANIC_REBOOT_SEC}s, smartd on"
}

verify() { watchdog_on && panic_on && smartd_on; }

uninstall() {
  run_sudo rm -f "$WATCHDOG_DEST" "$PANIC_DEST"
  run_sudo systemctl daemon-reexec
  run_sudo sysctl -w kernel.panic=0
}
