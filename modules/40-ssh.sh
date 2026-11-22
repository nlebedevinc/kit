# shellcheck shell=bash disable=SC2154  # HOST_USER, HOST_NAME come from the config
# 40-ssh (log §5.2–5.3): key-only SSH, no root login.
# Safety gate: passwords stay on until ~/.ssh/authorized_keys has a key;
# the drop-in is validated with sshd -t before the restart and rolled back if bad.
# beast-check: ssh.passwords, svc.ssh.socket.

DROPIN=/etc/ssh/sshd_config.d/99-hardening.conf
SRC="$BEAST_ROOT/config/ssh/99-hardening.conf"

describe() { echo "Key-only SSH login, no root login (socket activated)"; }

has_key() {
  [ -f "$HOME/.ssh/authorized_keys" ] &&
    grep -Eq '(^|[[:space:]])(ssh-(ed25519|rsa|dss)|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) AAAA' "$HOME/.ssh/authorized_keys"
}

socket_enabled() { [ "$(systemctl is-enabled ssh.socket 2>/dev/null)" = enabled ]; }

check() {
  apt_installed openssh-server && socket_enabled && file_same "$SRC" "$DROPIN"
}

plan() {
  apt_installed openssh-server || echo "apt-get install -y openssh-server"
  socket_enabled || echo "systemctl enable --now ssh.socket"
  if ! file_same "$SRC" "$DROPIN"; then
    if has_key; then
      echo "install $DROPIN (no passwords, no root login); sshd -t; systemctl restart ssh"
    else
      echo "blocked until ~/.ssh/authorized_keys has a key (manual action: ssh-copy-id from the client)"
    fi
  fi
}

apply() {
  local backup=''
  apt_installed openssh-server || apt_get install openssh-server
  # ssh.service reporting "disabled" is expected: ssh.socket starts it (log §5.3).
  socket_enabled || run_sudo systemctl enable --now ssh.socket
  file_same "$SRC" "$DROPIN" && return 0

  if ! has_key; then
    err "blocked: not turning off SSH passwords, ~/.ssh/authorized_keys has no key yet"
    manual_action ssh.copy_id "On your client, run: ssh-copy-id $HOST_USER@$HOST_NAME (if ssh-keygen offers to overwrite an existing key, answer n). Then run: beast install ssh"
    module_message "no key in ~/.ssh/authorized_keys yet"
    return "$MOD_BLOCKED"
  fi

  if [ -e "$DROPIN" ]; then
    backup="$DROPIN.bak.$(timestamp)"
    run_sudo cp -p "$DROPIN" "$backup"
  fi
  run_sudo mkdir -p "${DROPIN%/*}"
  run_sudo install -m 644 "$SRC" "$DROPIN"
  run_sudo mkdir -p /run/sshd # sshd -t needs it; with socket activation it may not exist
  if ! run_sudo sshd -t; then
    err "sshd -t rejected the configuration; rolling back $DROPIN"
    if [ -n "$backup" ]; then run_sudo mv "$backup" "$DROPIN"; else run_sudo rm -f "$DROPIN"; fi
    return 1
  fi
  run_sudo systemctl restart ssh
  module_message "keys only, no root login"
}

verify() {
  local t
  t=$(sudo sshd -T 2>/dev/null)
  printf '%s\n' "$t" | grep -qx 'passwordauthentication no' &&
    printf '%s\n' "$t" | grep -qx 'permitrootlogin no' &&
    socket_enabled
}
