# shellcheck shell=bash
# Ubuntu helpers (apt). Sourced by bin/kit after lib/common.sh.

# apt_missing PKG...: print the packages that aren't installed.
apt_missing() {
  local p
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || printf '%s\n' "$p"
  done
}

apt_installed() { [ -z "$(apt_missing "$@")" ]; }

apt_update() { run_sudo apt-get update; }

# apt_install PKG...: install only what's missing.
apt_install() {
  local missing
  missing=$(apt_missing "$@" | tr '\n' ' ')
  if [ -z "${missing// /}" ]; then
    info "Already installed: $*"
    return 0
  fi
  # shellcheck disable=SC2086  # word splitting of the package list is intended
  run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y $missing
}

apt_full_upgrade() { run_sudo env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y; }

reboot_required_notice() {
  if [ -f /var/run/reboot-required ]; then
    warn "A reboot is needed to finish the updates (sudo reboot)."
  fi
}
