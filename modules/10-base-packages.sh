# shellcheck shell=bash
# 10-base-packages (log §3, plus smartmontools from §11.3).

PACKAGES="openssh-server build-essential git curl tmux htop btop nvtop lm-sensors smartmontools"

describe() { echo "System upgrade and the base packages"; }

# shellcheck disable=SC2086  # package list
check() { have dpkg-query && apt_installed $PACKAGES; }

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

verify() { check; }
