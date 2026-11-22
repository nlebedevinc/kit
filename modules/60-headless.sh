# shellcheck shell=bash disable=SC2154  # HOST_USER, HOST_NAME come from the config
# 60-headless (log §6.2–6.3): never sleep; boot to the command line.
# Safety gate (SPEC §6.2): Tailscale Running, ssh.socket enabled, sleep masked.
# Never reboots. beast-check: sleep, boot.target.

describe() { echo "No sleep; boots to the command line (desktop off)"; }

headless_target() { [ "$(systemctl get-default 2>/dev/null)" = multi-user.target ]; }

check() { sleep_masked && headless_target; }

plan() {
  # shellcheck disable=SC2086
  sleep_masked || echo "systemctl mask $SLEEP_TARGETS"
  headless_target || echo "after the safety gate (Tailscale Running, ssh.socket enabled, sleep masked) and a confirmation: systemctl set-default multi-user.target; report reboot_required"
}

apply() {
  # shellcheck disable=SC2086
  sleep_masked || run_sudo systemctl mask $SLEEP_TARGETS
  headless_target && return 0

  if ! headless_gate; then
    module_message "safety gate: Tailscale must be Running and ssh.socket enabled first"
    return "$MOD_BLOCKED"
  fi
  if ! is_ssh_session; then
    info "You're at the machine. Before going headless, test from your client: ssh $HOST_USER@$HOST_NAME"
  fi
  if ! confirm_safety "Boot to the command line from the next boot on? (desktop: beast gui on)"; then
    if interactive; then
      module_message "not confirmed"
    else
      manual_action headless.confirm "Confirm going headless: run beast install headless --yes (or interactively)"
      module_message "needs --yes"
    fi
    return "$MOD_MANUAL"
  fi
  run_sudo systemctl set-default multi-user.target
  module_message "boots to the command line; the desktop stays until the next boot"
  reboot_required
}

verify() { check; }

# Sleep allowed again; the desktop starts at the next boot (now: beast gui start).
uninstall() {
  # shellcheck disable=SC2086
  run_sudo systemctl unmask $SLEEP_TARGETS
  run_sudo systemctl set-default graphical.target
}
