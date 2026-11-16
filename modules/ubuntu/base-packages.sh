# shellcheck shell=bash disable=SC2154  # BASE_PACKAGES comes from host.conf
# base-packages (SETUP-LOG §3): full upgrade on first install, then the base tools.
# Later upgrades run through `kit update`, so a second `kit install` changes nothing.

describe() { echo "Update the system and install base packages"; }

check() {
  # shellcheck disable=SC2086
  apt_installed $BASE_PACKAGES
}

apply() {
  apt_update
  apt_full_upgrade
  # shellcheck disable=SC2086
  apt_install $BASE_PACKAGES
  reboot_required_notice
}

update() {
  header "base-packages" "system update"
  apt_update
  apt_full_upgrade
  reboot_required_notice
}

verify() {
  local missing
  # shellcheck disable=SC2086
  missing=$(apt_missing $BASE_PACKAGES | tr '\n' ' ')
  if [ -z "${missing// /}" ]; then
    report ok "Base packages installed"
  else
    report fail "Missing packages: $missing" "kit install base-packages"
  fi
  if [ -f /var/run/reboot-required ]; then
    report info "A reboot is pending to finish updates" "sudo reboot"
  fi
  report_status
}
