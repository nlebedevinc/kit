# shellcheck shell=bash
# nvidia (SETUP-LOG §4): verify the driver. Install it only with --fix.
# nvidia-persistenced is a static unit started by udev; nothing to enable.

describe() { echo "Check the NVIDIA driver (nvidia-smi)"; }

applies() {
  if have nvidia-smi || { have lspci && lspci 2>/dev/null | grep -qi nvidia; }; then
    return 0
  fi
  echo "no NVIDIA GPU found"
  return 1
}

check() { nvidia-smi >/dev/null 2>&1; }

apply() {
  warn "nvidia-smi doesn't work: the NVIDIA driver isn't installed or isn't loaded."
  if [ "$KIT_FIX" != 1 ]; then
    info "Fix: sudo ubuntu-drivers install, then reboot. Or let kit do it: kit install nvidia --fix"
    return 1
  fi
  run_sudo ubuntu-drivers install
  info "The driver loads after a reboot. Then run kit install again."
  maybe_reboot
  return "$KIT_SKIPPED"
}

verify() {
  local out
  if out=$(nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total --format=csv,noheader 2>/dev/null); then
    report ok "GPU: $out"
  else
    report fail "GPU: nvidia-smi failed" "sudo ubuntu-drivers install, then reboot (or: kit install nvidia --fix)"
  fi
  report_status
}
