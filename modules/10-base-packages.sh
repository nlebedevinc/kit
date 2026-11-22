# shellcheck shell=bash
# shellcheck disable=SC2154  # BASE_PACKAGES comes from the config
# 10-base-packages (log §3, plus smartmontools from §11.3). The list is BASE_PACKAGES.
# `beast update` sets BEAST_UPGRADE=1, so the system is upgraded on every update too.

PACKAGES=$BASE_PACKAGES

describe() { echo "System upgrade and the base packages"; }

# shellcheck disable=SC2086  # package list
check() { [ "${BEAST_UPGRADE:-0}" != 1 ] && have dpkg-query && apt_installed $PACKAGES; }

plan() {
  local missing
  # shellcheck disable=SC2086
  missing=$(apt_missing $PACKAGES)
  echo "apt-get update"
  echo "apt-get full-upgrade -y"
  echo "apt-get install -y ${missing:-$PACKAGES}"
}

apply() {
  apt_get update
  apt_get full-upgrade
  # shellcheck disable=SC2086
  apt_get install $PACKAGES
  if [ -f /var/run/reboot-required ]; then reboot_required; fi
}

# shellcheck disable=SC2086
verify() { apt_installed $PACKAGES; }
