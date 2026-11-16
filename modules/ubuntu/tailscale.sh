# shellcheck shell=bash disable=SC2154  # TAILSCALE_INSTALL_URL comes from host.conf
# tailscale (SETUP-LOG §5.1): install with the official script, then `tailscale up`.
# TAILSCALE_AUTHKEY (environment only) allows unattended runs; it's never printed.

describe() { echo "Install Tailscale and connect this machine"; }

check() { have tailscale && tailscale status >/dev/null 2>&1; }

apply() {
  if ! have tailscale; then
    info "Installing Tailscale with the official script ($TAILSCALE_INSTALL_URL)"
    run_cmd sh -c "curl -fsSL '$TAILSCALE_INSTALL_URL' | sh"
  fi
  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    kit_secret "$TAILSCALE_AUTHKEY"
    run_sudo tailscale up "--authkey=$TAILSCALE_AUTHKEY"
  else
    info "Sign in through the link Tailscale prints."
    run_sudo tailscale up
  fi
  key_expiry_reminder
}

key_expiry_reminder() {
  warn "Disable key expiry for this machine, or it drops off Tailscale in ~6 months:"
  info "https://login.tailscale.com/admin/machines → $(current_hostname) → ⋯ → Disable key expiry"
}

verify() {
  if have tailscale && tailscale status >/dev/null 2>&1; then
    report ok "Tailscale is connected"
  else
    report fail "Tailscale isn't connected" "kit install tailscale"
  fi
  report info "Key expiry can't be checked from here" "admin console → Machines → $(current_hostname) → ⋯ → Disable key expiry"
  report_status
}
