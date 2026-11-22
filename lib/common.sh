# shellcheck shell=bash
# beast shared helpers: logging, running commands, files, prompts, config, the lock,
# sudo, and the records modules leave for the summary (manual actions, reboot).
# Sourced by bin/beast and, through it, by every module. Needs lib/output.sh first.

BEAST_DRY_RUN=${BEAST_DRY_RUN:-0}
BEAST_YES=${BEAST_YES:-0}
BEAST_FIX=${BEAST_FIX:-0}
BEAST_VERBOSE=${BEAST_VERBOSE:-0}
BEAST_NONINTERACTIVE=${BEAST_NONINTERACTIVE:-0}
BEAST_STATE_DIR=${BEAST_STATE_DIR:-$HOME/.local/state/beast}
BEAST_LOG=${BEAST_LOG:-$BEAST_STATE_DIR/install.log}

# ---------------------------------------------------------------- logging (stderr + install.log)

_log_file() {
  [ -d "${BEAST_LOG%/*}" ] || return 0
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$BEAST_LOG" 2>/dev/null || true
}
log() {
  printf '%s\n' "$*" >&2
  _log_file "$*"
}
step() {
  printf '%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2
  _log_file "==> $*"
}
info() {
  printf '    %s\n' "$*" >&2
  _log_file "$*"
}
warn() {
  printf '    %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
  _log_file "warning: $*"
}
err() {
  printf '%sbeast:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  _log_file "error: $*"
}
die() {
  err "$1"
  exit "${2:-$EXIT_FAIL}"
}

# ---------------------------------------------------------------- running commands

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date +%Y%m%d%H%M%S; }

# run_cmd CMD...: run it, or under --dry-run print what would run (stdout).
# Never pass secrets to it: they would be on a command line.
run_cmd() {
  if [ "$BEAST_DRY_RUN" = 1 ]; then
    printf 'would run: %s\n' "$*"
    return 0
  fi
  _log_file "+ $*"
  if [ "$BEAST_VERBOSE" = 1 ]; then printf '    %s+ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; fi
  "$@"
}

run_sudo() { run_cmd sudo "$@"; }

# apt_get ARGS...: apt-get as root, never asking anything.
apt_get() {
  run_sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold "$@"
}

# apt_missing PKG...: the packages that aren't installed, space-separated.
apt_missing() {
  local p out=''
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || out="$out${out:+ }$p"
  done
  printf '%s' "$out"
}
apt_installed() { [ -z "$(apt_missing "$@")" ]; }

# ---------------------------------------------------------------- files

file_same() { [ -f "$2" ] && cmp -s "$1" "$2"; }

# install_file SRC DEST [MODE]: copy as root when the content differs, keeping a backup.
install_file() {
  local src=$1 dest=$2 mode=${3:-644}
  if file_same "$src" "$dest"; then return 0; fi
  if [ -e "$dest" ]; then run_sudo cp -p "$dest" "$dest.bak.$(timestamp)"; fi
  run_sudo mkdir -p "${dest%/*}"
  run_sudo install -m "$mode" "$src" "$dest"
  info "installed $dest"
}

# render_file DEST [MODE] <<<CONTENT: like install_file, with the content on stdin.
render_file() {
  local dest=$1 mode=${2:-644} tmp rc=0
  tmp=$(mktemp)
  cat >"$tmp"
  install_file "$tmp" "$dest" "$mode" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

# same_content DEST <<<CONTENT: DEST has exactly this content.
same_content() {
  local tmp rc=0
  tmp=$(mktemp)
  cat >"$tmp"
  file_same "$tmp" "$1" || rc=1
  rm -f "$tmp"
  return "$rc"
}

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------- session and prompts

# interactive: a person can answer prompts.
interactive() { [ "$BEAST_NONINTERACTIVE" != 1 ] && [ -t 0 ]; }

is_ssh_session() { [ -n "${SSH_CONNECTION:-}" ]; }

# ask QUESTION: y/N on the terminal. Never called without one.
ask() {
  local reply=''
  interactive || return 1
  printf '    %s [y/N] ' "$1" >&2
  IFS= read -r reply || reply=''
  case $reply in [Yy] | [Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# confirm QUESTION: a non-safety confirmation. --yes answers it.
confirm() {
  if [ "$BEAST_YES" = 1 ]; then
    info "$1 yes (--yes)"
    return 0
  fi
  ask "$1"
}

# confirm_safety QUESTION: interactive: always asked, even with --yes.
# Non-interactive: only --yes counts. The caller checks the safety gate first.
confirm_safety() {
  if interactive; then
    ask "$1"
  else
    [ "$BEAST_YES" = 1 ]
  fi
}

# read_secret VAR PROMPT: read without echo (TTY only). Never logged.
read_secret() {
  local __var=$1 __val=''
  interactive || return 1
  printf '    %s: ' "$2" >&2
  IFS= read -rs __val || return 1
  printf '\n' >&2
  printf -v "$__var" '%s' "$__val"
}

# ---------------------------------------------------------------- records for the summary

# manual_action ID INSTRUCTION [URL]: something only a person can do.
manual_action() {
  local line
  line="{\"id\":$(json_str "$1"),\"instruction\":$(json_str "$2")"
  if [ -n "${3:-}" ]; then line="$line,\"url\":$(json_str "$3")"; fi
  line="$line}"
  if [ -n "${BEAST_RUN_DIR:-}" ]; then
    printf '%s\n' "$line" >>"$BEAST_RUN_DIR/manual"
    printf '%s\n' "$2${3:+ ($3)}" >>"$BEAST_RUN_DIR/manual.txt"
  fi
  info "${C_YELLOW}manual action:${C_RESET} $2${3:+ ($3)}"
}

# reboot_required: beast never reboots; the summary says so instead.
reboot_required() {
  if [ -n "${BEAST_RUN_DIR:-}" ]; then : >"$BEAST_RUN_DIR/reboot"; fi
  info "a reboot is needed to finish this (beast never reboots by itself)"
}

# module_message TEXT: the one-line message in this module's event.
module_message() {
  if [ -n "${BEAST_RUN_DIR:-}" ]; then printf '%s' "$*" >"$BEAST_RUN_DIR/message"; fi
}

# ---------------------------------------------------------------- config

beast_config_path() {
  printf '%s' "${BEAST_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/beast/beast.conf}"
}

# _config_value RAW: the value of KEY=RAW. Quotes are stripped; nothing is expanded.
_config_value() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  case $v in
    \"*)
      v=${v#\"}
      v=${v%%\"*}
      ;;
    \'*)
      v=${v#\'}
      v=${v%%\'*}
      ;;
    *)
      v=${v%%[[:space:]]#*}
      v=${v%"${v##*[![:space:]]}"}
      ;;
  esac
  printf '%s' "$v"
}

# config_keys: every key the example config defines (the allowed keys).
config_keys() {
  sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$BEAST_ROOT/config/beast.conf.example"
}

# config_parse FILE [ALLOWED_KEYS]: set KEY=VALUE lines as shell variables.
# The file is parsed, not sourced, because beast-check reads it as root.
config_parse() {
  local file=$1 allowed=${2:-} line key
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    if [ -n "$allowed" ] && ! printf '%s\n' "$allowed" | grep -qx "$key"; then
      warn "$file: unknown setting $key (ignored)"
      continue
    fi
    printf -v "$key" '%s' "$(_config_value "${BASH_REMATCH[2]}")"
  done <"$file"
}

# load_config: defaults from config/beast.conf.example, then the user's file.
load_config() {
  BEAST_CONFIG=$(beast_config_path)
  export BEAST_CONFIG
  config_parse "$BEAST_ROOT/config/beast.conf.example"
  if [ -r "$BEAST_CONFIG" ]; then config_parse "$BEAST_CONFIG" "$(config_keys)"; fi
}

# ---------------------------------------------------------------- lock and sudo

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "don't run beast as root. Run it as your normal user; it uses sudo when needed."
  fi
}

# take_lock: one beast run at a time. The lock is held on
# fd 9 until this process and its children exit.
take_lock() {
  mkdir -p "$BEAST_STATE_DIR"
  have flock || {
    warn "flock isn't installed; not locking"
    return 0
  }
  exec 9>"$BEAST_STATE_DIR/lock"
  flock -n 9 || die "another beast run holds the lock ($BEAST_STATE_DIR/lock)" "$EXIT_LOCKED"
}

# ensure_sudo: interactive: ask for the password once and keep it fresh.
# Non-interactive: sudo must already work without a password.
ensure_sudo() {
  [ "$BEAST_DRY_RUN" != 1 ] || return 0
  [ -z "${BEAST_SUDO_READY:-}" ] || return 0
  have sudo || die "sudo is required"
  if interactive; then
    sudo -v || die "sudo failed"
  elif ! sudo -n true 2>/dev/null; then
    die "sudo needs a password and there's no terminal. Run \`sudo -v\` in this session first, or connect with \`ssh -t\`." "$EXIT_SUDO"
  fi
  # Keep sudo fresh while beast runs. fd 9 (the lock) is closed in here, or a
  # sleeping keepalive would hold the lock after beast exits.
  (
    exec 9>&-
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true 2>/dev/null
      sleep 50
    done
  ) </dev/null >/dev/null 2>&1 &
  export BEAST_SUDO_READY=1
}

# ---------------------------------------------------------------- system facts

os_release_value() {
  local file=${BEAST_OS_RELEASE:-/etc/os-release}
  [ -r "$file" ] || return 0
  sed -n "s/^$1=//p" "$file" | head -n 1 | sed 's/^"//; s/"$//'
}

# ts_field PATH: a field of `tailscale status --json`, e.g. BackendState or Self.ID.
ts_field() {
  have tailscale || return 0
  tailscale status --json 2>/dev/null | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].split("."):
    v = v.get(k) if isinstance(v, dict) else None
print("" if v is None else v)
' "$1" 2>/dev/null || true
}

SLEEP_TARGETS="sleep.target suspend.target hibernate.target hybrid-sleep.target"

sleep_masked() {
  local t
  for t in $SLEEP_TARGETS; do
    [ "$(systemctl is-enabled "$t" 2>/dev/null)" = masked ] || return 1
  done
}

# headless_gate: Tailscale Running, ssh.socket enabled, sleep masked.
headless_gate() {
  local ok=0
  if [ "$(ts_field BackendState)" != Running ]; then
    err "blocked: Tailscale isn't Running (beast install tailscale)"
    ok=1
  fi
  if [ "$(systemctl is-enabled ssh.socket 2>/dev/null)" != enabled ]; then
    err "blocked: ssh.socket isn't enabled (beast install ssh)"
    ok=1
  fi
  if ! sleep_masked; then
    err "blocked: sleep isn't masked"
    ok=1
  fi
  return "$ok"
}

# rgb_hardware: the MSI MYSTIC LIGHT controller (USB 0db0:0076, log §8.1) is present.
rgb_hardware() { have lsusb && lsusb -d 0db0:0076 >/dev/null 2>&1; }
