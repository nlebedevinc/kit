# shellcheck shell=bash disable=SC2154  # HOST_USER/HOST_NAME come from host.conf
# ssh (SETUP-LOG §5.2–5.3): key-only SSH login.
#
# Safety (SPEC §8.1): password login is only turned off when
# ~/.ssh/authorized_keys holds a key and, in a local session, the user confirms a
# key login from the client works. The drop-in is validated with `sshd -t`
# before the restart and rolled back if sshd rejects it.
#
# Note: in sshd_config.d the FIRST file that sets a value wins, so another file
# (e.g. 50-cloud-init.conf) can override 99-hardening.conf. verify() checks the
# effective values with `sshd -T` and names any file that gets in the way.

DROPIN=/etc/ssh/sshd_config.d/99-hardening.conf

describe() { echo "Key-only SSH login (password login off, no root login)"; }

ssh_unit() {
  if systemctl cat ssh.socket >/dev/null 2>&1; then echo ssh.socket; else echo ssh.service; fi
}

has_authorized_key() {
  local f="$HOME/.ssh/authorized_keys"
  [ -f "$f" ] && grep -Eq '(^|[[:space:]])(ssh-(ed25519|rsa|dss)|ecdsa-sha2-[a-z0-9-]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/=]{20,}' "$f"
}

# sshd -T and sshd -t need /run/sshd, which socket activation only creates on the
# first connection.
ensure_privsep_dir() {
  [ -d /run/sshd ] || run_sudo install -d -m 0755 /run/sshd
}

effective() { sudo -n sshd -T 2>/dev/null | grep -Ei "^$1 " | awk '{print tolower($2)}'; }

hardening_effective() {
  [ "$(effective passwordauthentication)" = no ] &&
    [ "$(effective kbdinteractiveauthentication)" = no ] &&
    [ "$(effective permitrootlogin)" = no ]
}

check() {
  apt_installed openssh-server &&
    [ "$(systemctl is-enabled "$(ssh_unit)" 2>/dev/null)" = enabled ] &&
    file_same "$(host_file ssh/99-hardening.conf)" "$DROPIN" &&
    hardening_effective
}

client_instructions() {
  local user=${HOST_USER:-$USER} host=${HOST_NAME:-$(current_hostname)}
  info "On your client (e.g. the Mac), copy your public key to this machine:"
  info "    ssh-copy-id $user@$host"
  info "If ssh-keygen offers to overwrite an existing key, answer n and reuse it."
  info "Then check it: ssh $user@$host   (should log in without a password)"
}

apply() {
  local src prev='' unit
  src=$(host_file ssh/99-hardening.conf)

  apt_install openssh-server
  unit=$(ssh_unit)
  if [ "$(systemctl is-enabled "$unit" 2>/dev/null)" != enabled ]; then
    run_sudo systemctl enable --now "$unit"
  fi

  # Safety gate.
  if ! has_authorized_key; then
    err "No key in ~/.ssh/authorized_keys, so password login stays on (otherwise you'd be locked out)."
    client_instructions
    info "Then run: kit install ssh"
    return "$KIT_BLOCKED"
  fi
  if [ "${KIT_SESSION:-local}" != ssh ]; then
    if [ "$KIT_DRY_RUN" = 1 ]; then
      info "would ask: have you logged in with your key from the client?"
    elif ! confirm_always "Running locally. Have you logged in from your client with 'ssh ${HOST_USER:-$USER}@${HOST_NAME:-$(current_hostname)}' using your key?"; then
      client_instructions
      return "$KIT_BLOCKED"
    fi
  fi

  if ! file_same "$src" "$DROPIN"; then
    if [ -e "$DROPIN" ]; then
      prev="$DROPIN.bak.$(timestamp)"
      run_sudo cp -p "$DROPIN" "$prev"
    fi
    run_sudo install -m 644 "$src" "$DROPIN"
  fi

  ensure_privsep_dir
  if [ "$KIT_DRY_RUN" != 1 ] && ! sudo sshd -t; then
    err "sshd rejected the configuration; rolling back."
    if [ -n "$prev" ]; then run_sudo mv "$prev" "$DROPIN"; else run_sudo rm -f "$DROPIN"; fi
    return 1
  fi
  [ "$KIT_DRY_RUN" = 1 ] && info "would check the config with: sudo sshd -t"
  run_sudo systemctl restart ssh
  info "Existing SSH sessions stay connected."
}

overriding_files() {
  sudo -n grep -liE '^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|PermitRootLogin)[[:space:]]+yes' \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tr '\n' ' '
}

verify() {
  local unit pa kbd root
  unit=$(ssh_unit)
  if [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ]; then
    report ok "SSH: $unit enabled"
  else
    report fail "SSH: $unit not enabled" "sudo systemctl enable --now $unit"
  fi
  if ! sudo -n true 2>/dev/null; then
    report fail "SSH hardening: needs sudo to check" "run kit doctor in a terminal where sudo can ask"
  else
    pa=$(effective passwordauthentication)
    kbd=$(effective kbdinteractiveauthentication)
    root=$(effective permitrootlogin)
    if [ "$pa" = no ] && [ "$kbd" = no ] && [ "$root" = no ]; then
      report ok "SSH hardening: passwordauthentication no, kbdinteractiveauthentication no, permitrootlogin no"
    else
      report fail "SSH hardening: passwordauthentication ${pa:-?}, kbdinteractiveauthentication ${kbd:-?}, permitrootlogin ${root:-?}" \
        "kit install ssh$([ -n "$(overriding_files)" ] && printf '; these files turn it back on: %s' "$(overriding_files)")"
    fi
  fi
  if infocmp xterm-ghostty >/dev/null 2>&1; then
    report ok "Ghostty terminfo installed"
  else
    report info "Ghostty terminfo not installed (nvtop etc. fail with TERM=xterm-ghostty)" \
      "on the Mac: infocmp -x xterm-ghostty | ssh ${HOST_USER:-$USER}@${HOST_NAME:-$(current_hostname)} -- tic -x -"
  fi
  report_status
}
