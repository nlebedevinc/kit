# shellcheck shell=bash disable=SC2154  # HOST_USER/HOST_NAME come from host.conf
# headless (SETUP-LOG §6.2–6.3): never sleep, boot to the command line.
#
# Safety (SPEC §8.2): the boot target only changes when Tailscale is up, SSH is
# enabled and sleep is masked. Never reboots without asking.
# The desktop stays installed: `kit gui start` (now) or `kit gui on` (at boot).

SLEEP_TARGETS="sleep.target suspend.target hibernate.target hybrid-sleep.target"

describe() { echo "Never sleep; boot to the command line (desktop stays available)"; }

sleep_masked() {
  local t
  for t in $SLEEP_TARGETS; do
    [ "$(systemctl is-enabled "$t" 2>/dev/null)" = masked ] || return 1
  done
}

boot_headless() { [ "$(systemctl get-default 2>/dev/null)" = multi-user.target ]; }

ssh_enabled() {
  [ "$(systemctl is-enabled ssh.socket 2>/dev/null)" = enabled ] ||
    [ "$(systemctl is-enabled ssh.service 2>/dev/null)" = enabled ]
}

check() { sleep_masked && boot_headless; }

apply() {
  local problems=''
  if ! sleep_masked; then
    # shellcheck disable=SC2086  # list of units
    run_sudo systemctl mask $SLEEP_TARGETS
  fi
  boot_headless && return 0

  # Safety gate.
  if ! { have tailscale && tailscale status >/dev/null 2>&1; }; then
    problems="$problems"$'\n'"      - Tailscale isn't connected (kit install tailscale)"
  fi
  ssh_enabled || problems="$problems"$'\n'"      - SSH isn't enabled (kit install ssh)"
  if [ "$KIT_DRY_RUN" != 1 ] && ! sleep_masked; then
    problems="$problems"$'\n'"      - sleep isn't masked"
  fi
  if [ -n "$problems" ]; then
    err "Not switching to the command line yet; you could lose remote access:$problems"
    return "$KIT_BLOCKED"
  fi

  if [ "${KIT_SESSION:-local}" != ssh ]; then
    warn "You're on the local screen. Before going headless, test from your client: ssh ${HOST_USER:-$USER}@${HOST_NAME:-$(current_hostname)}"
  fi
  if [ "$KIT_DRY_RUN" != 1 ] && ! confirm "Boot to the command line from now on (no desktop on the screen)?"; then
    info "Left as is. Run kit install headless when you're ready."
    return "$KIT_SKIPPED"
  fi
  run_sudo systemctl set-default multi-user.target
  info "Desktop when you need it: kit gui start (now) · kit gui on (at boot)"
  if [ "$KIT_DRY_RUN" = 1 ]; then
    info "would ask before rebooting"
  else
    maybe_reboot "Reboot now to start headless?"
  fi
}

uninstall() {
  # shellcheck disable=SC2086
  run_sudo systemctl unmask $SLEEP_TARGETS
  run_sudo systemctl set-default graphical.target
  info "Sleep allowed again; the desktop starts at the next boot (or now: kit gui start)."
}

verify() {
  if [ "$(systemctl get-default 2>/dev/null)" = multi-user.target ]; then
    report ok "Boot target: multi-user.target"
  else
    report fail "Boot target: $(systemctl get-default 2>/dev/null || echo unknown)" "kit install headless"
  fi
  if sleep_masked; then
    report ok "Sleep: masked"
  else
    report fail "Sleep: not masked" "kit install headless"
  fi
  report_status
}
