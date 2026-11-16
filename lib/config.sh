# shellcheck shell=bash
# Host resolution and config loading (SPEC §6).
# Layers, later wins: hosts/<host>/host.conf → ~/.config/kit/kit.conf → environment.

kit_user_config() { printf '%s/kit/kit.conf\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

valid_name() {
  case $1 in '' | -* | .* | *[!a-zA-Z0-9._-]*) return 1 ;; esac
  return 0
}

kit_hosts() {
  local d
  # shellcheck disable=SC2153  # KIT_ROOT is set by bin/kit
  for d in "$KIT_ROOT"/hosts/*/; do
    [ -f "$d/host.conf" ] && basename "$d"
  done
  return 0
}

host_exists() { valid_name "$1" && [ -f "$KIT_ROOT/hosts/$1/host.conf" ]; }

# _conf_get FILE KEY: KEY's value after sourcing FILE in a subshell.
_conf_get() {
  local file=$1 key=$2
  [ -f "$file" ] || return 0
  (
    set +eu
    # shellcheck source=/dev/null
    . "$file" >/dev/null 2>&1
    printf '%s' "${!key:-}"
  )
}

# resolve_host [FLAG_VALUE]: --host → $KIT_HOST → user config → hostname → ask.
resolve_host() {
  local h=${1:-} hosts
  [ -n "$h" ] || h=${KIT_HOST:-}
  [ -n "$h" ] || h=$(_conf_get "$(kit_user_config)" KIT_HOST)
  hosts=$(kit_hosts | tr '\n' ' ')
  if [ -n "$h" ]; then
    if host_exists "$h"; then
      printf '%s\n' "$h"
      return 0
    fi
    err "Unknown host '$h'. Available: ${hosts:-none}"
    return 2
  fi
  h=$(current_hostname)
  if host_exists "$h"; then
    printf '%s\n' "$h"
    return 0
  fi
  if has_tty && [ -n "$hosts" ]; then
    printf '    No host profile is named after this machine (%s).\n    Which one should kit use? (%s) ' "$h" "${hosts% }" >/dev/tty
    IFS= read -r h </dev/tty || h=
    if host_exists "$h"; then
      printf '%s\n' "$h"
      return 0
    fi
  fi
  err "No host profile matches this machine ('$(current_hostname)'). Pass --host NAME. Available: ${hosts:-none}"
  return 2
}

# config_keys FILE...: every KEY= assigned in the files.
config_keys() {
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' "$f"
  done | sort -u
}

# load_config HOST: set KIT_HOST, KIT_HOST_DIR and every config value.
load_config() {
  local host=$1 host_conf user_conf key saved=''
  host_conf="$KIT_ROOT/hosts/$host/host.conf"
  user_conf=$(kit_user_config)
  host_exists "$host" || die "Unknown host '$host'" 2

  KIT_CONFIG_KEYS=$(config_keys "$host_conf" "$user_conf" | tr '\n' ' ')
  # Values already in the environment win over both files.
  for key in $KIT_CONFIG_KEYS; do
    case $key in KIT_HOST | KIT_HOST_DIR | KIT_ROOT) continue ;; esac
    if [ -n "${!key+x}" ]; then
      saved="$saved$key=$(printf '%q' "${!key}")"$'\n'
    fi
  done

  # shellcheck source=/dev/null
  . "$host_conf"
  if [ -f "$user_conf" ]; then
    # shellcheck source=/dev/null
    . "$user_conf"
  fi
  eval "$saved"

  KIT_HOST=$host
  # shellcheck disable=SC2034  # used by bin/kit and modules
  KIT_HOST_DIR="$KIT_ROOT/hosts/$host"
  KIT_OS=${KIT_OS:-}
  KIT_MODULES=${KIT_MODULES:-}
  [ -n "$KIT_OS" ] || die "$host_conf doesn't set KIT_OS"
}

# is_secret_key KEY: config names whose values are never printed.
is_secret_key() {
  case $1 in *PASSWORD* | *PASSWD* | *PSK* | *SECRET* | *TOKEN* | *AUTHKEY* | *AUTH_KEY*) return 0 ;; esac
  return 1
}
