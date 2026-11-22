# shellcheck shell=bash disable=SC2154  # HOST_NAME comes from the config
# 30-tailscale (log §5.1, §11.4): install, log in, disable key expiry.
# Secrets (TAILSCALE_AUTHKEY, TS_API_TOKEN) come only from the environment and are
# handed over on stdin, never as arguments. beast-check: tailscale, tailscale.expiry.

INSTALL_URL=https://tailscale.com/install.sh
ADMIN_URL=https://login.tailscale.com/admin/machines

describe() { echo "Tailscale: installed, logged in, key expiry disabled"; }

running() { [ "$(ts_field BackendState)" = Running ]; }

check() {
  have tailscale && running && [ -z "$(ts_field Self.KeyExpiry)" ]
}

plan() {
  have tailscale || echo "install Tailscale: curl -fsSL $INSTALL_URL | sh"
  if ! have tailscale || ! running; then
    if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
      echo "sudo tailscale up --auth-key=file:/dev/stdin (key from TAILSCALE_AUTHKEY)"
    elif interactive; then
      echo "sudo tailscale up (sign in through the printed link)"
    else
      echo "sudo tailscale up: report the login URL as a manual action"
    fi
  fi
  if [ -n "${TS_API_TOKEN:-}" ]; then
    echo "disable key expiry through the Tailscale API (TS_API_TOKEN)"
  else
    echo "if key expiry is on: manual action (admin console)"
  fi
}

login() {
  local out url
  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    info "Logging in with TAILSCALE_AUTHKEY"
    printf '%s' "$TAILSCALE_AUTHKEY" | sudo tailscale up --auth-key=file:/dev/stdin
  elif interactive; then
    info "Sign in through the link tailscale prints"
    sudo tailscale up
  else
    out=$(sudo tailscale up --timeout=15s 2>&1 </dev/null || true)
    url=$(printf '%s\n' "$out" | grep -Eo 'https://login\.tailscale\.com/[^[:space:]]+' | head -n 1)
    [ -n "$url" ] || url=$(ts_field AuthURL)
    if [ -z "$url" ]; then
      err "tailscale up gave no login link: $out"
      return 1
    fi
    manual_action tailscale.login "Open this link and sign in to Tailscale, then run beast install tailscale again: $url" "$url"
    module_message "waiting for the Tailscale login"
    return "$MOD_MANUAL"
  fi
}

disable_expiry() {
  local id
  if [ -z "${TS_API_TOKEN:-}" ]; then
    manual_action tailscale.key_expiry "Admin console → Machines → $HOST_NAME → … → Disable key expiry" "$ADMIN_URL"
    module_message "key expiry is on"
    return "$MOD_MANUAL"
  fi
  id=$(ts_field Self.ID)
  [ -n "$id" ] || {
    err "can't find this node's ID in tailscale status"
    return 1
  }
  info "Disabling key expiry through the API"
  # The token goes in a curl config on stdin, not on the command line.
  printf 'user = "%s:"\n' "$TS_API_TOKEN" |
    curl --config - -fsS --max-time 30 -X POST -H 'Content-Type: application/json' \
      --data '{"keyExpiryDisabled": true}' "https://api.tailscale.com/api/v2/device/$id/key" >/dev/null || {
    err "the Tailscale API call failed (check TS_API_TOKEN)"
    return 1
  }
}

apply() {
  if ! have tailscale; then
    info "Installing Tailscale ($INSTALL_URL)"
    curl -fsSL --max-time 120 "$INSTALL_URL" | sh
  fi
  # The package enables tailscaled; make sure it's also running before logging in.
  if [ "$(systemctl is-active tailscaled 2>/dev/null)" != active ]; then
    run_sudo systemctl enable --now tailscaled
  fi
  running || login || return $?
  if [ -n "$(ts_field Self.KeyExpiry)" ]; then disable_expiry || return $?; fi
  module_message "Running as $(ts_field Self.HostName)"
}

verify() { running; }
