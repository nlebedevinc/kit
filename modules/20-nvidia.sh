# shellcheck shell=bash
# 20-nvidia (log §4): verify only. Installs the driver only with --fix.
# beast-check: gpu.

describe() { echo "Checks that the NVIDIA driver works (nvidia-smi)"; }

has_nvidia_gpu() { have lspci && [ -n "$(lspci -d 10de: 2>/dev/null)" ]; }

check() {
  local info name driver mem
  if ! has_nvidia_gpu; then
    module_message "no NVIDIA GPU found"
    return "$MOD_SKIPPED"
  fi
  have nvidia-smi || return 1
  info=$(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null | head -n 1) || return 1
  [ -n "$info" ] || return 1
  IFS=',' read -r name driver mem <<<"$info"
  module_message "$name, driver${driver},${mem}"
}

plan() {
  if [ "$BEAST_FIX" = 1 ]; then
    echo "sudo ubuntu-drivers install"
    echo "report reboot_required"
  else
    echo "nvidia-smi fails: report the fix (sudo ubuntu-drivers install, then reboot); --fix installs it"
  fi
}

apply() {
  if [ "$BEAST_FIX" != 1 ]; then
    err "nvidia-smi doesn't work. Fix: sudo ubuntu-drivers install, then reboot (or: beast install nvidia --fix)"
    module_message "nvidia-smi failed; fix: sudo ubuntu-drivers install, then reboot (or --fix)"
    return 1
  fi
  run_sudo ubuntu-drivers install
  module_message "driver installed; reboot to load it"
  reboot_required
}

# After --fix the driver loads only after a reboot.
verify() { [ -f "$BEAST_RUN_DIR/reboot" ] || check; }
