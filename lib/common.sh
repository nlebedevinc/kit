# shellcheck shell=bash
# kit shared helpers: logging, dry-run, sudo, prompts, files, OS detection.
# Sourced by bin/kit, modules and host commands. Must stay bash 3.2 compatible.

KIT_DRY_RUN=${KIT_DRY_RUN:-0}
KIT_YES=${KIT_YES:-0}
KIT_VERBOSE=${KIT_VERBOSE:-0}
KIT_FIX=${KIT_FIX:-0}
KIT_NO_COLOR=${KIT_NO_COLOR:-0}

# Module return codes, besides 0 (ok) and 1 (failed).
# shellcheck disable=SC2034  # used by modules
KIT_BLOCKED=3   # stopped by a safety gate
# shellcheck disable=SC2034
KIT_SKIPPED=5   # the user declined, or it has to wait (e.g. for a reboot)

KIT_SECRETS=()
KIT_REPORT_FAILED=0

# ---------------------------------------------------------------- output

kit_color_init() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$KIT_NO_COLOR" != 1 ]; then
    C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
    C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
  else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
  fi
}
kit_color_init

say()    { printf '%s\n' "$*"; }
info()   { printf '    %s\n' "$*"; }
ok()     { printf '    %s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()   { printf '    %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()    { printf '%skit:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()    { err "$1"; exit "${2:-1}"; }
header() { printf '\n%s==>%s %s%s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "${2:+: $2}"; }

# report ok|fail|info|skip LABEL [HINT]: one line of `kit doctor` output.
report() {
  local kind=$1 label=$2 hint=${3:-} mark
  case $kind in
    ok)   mark='✅' ;;
    fail) mark='❌'; KIT_REPORT_FAILED=1 ;;
    info) mark='ℹ️ ' ;;
    skip) mark='⏭ ' ;;
    *)    mark='? ' ;;
  esac
  printf '  %s %s\n' "$mark" "$label"
  if [ -n "$hint" ] && [ "$kind" != ok ]; then
    printf '     %s→ %s%s\n' "$C_DIM" "$hint" "$C_RESET"
  fi
}

# Exit status for a verify() that used report: 0 unless something failed.
report_status() { [ "$KIT_REPORT_FAILED" = 0 ]; }

# ---------------------------------------------------------------- running commands

# Register a value that must never be printed (auth keys, passwords).
kit_secret() { KIT_SECRETS+=("$1"); }

_kit_display() {
  local out s q
  out=$(printf '%q ' "$@")
  out=${out% }
  for s in ${KIT_SECRETS[@]+"${KIT_SECRETS[@]}"}; do
    [ -n "$s" ] || continue
    q=$(printf '%q' "$s")
    out=${out//"$q"/***}
    out=${out//"$s"/***}
  done
  printf '%s' "$out"
}

# run_cmd CMD...: execute, or only print it under --dry-run.
# (Not called `run`: that name belongs to the bats test runner.)
run_cmd() {
  if [ "$KIT_DRY_RUN" = 1 ]; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$(_kit_display "$@")"
    return 0
  fi
  if [ "$KIT_VERBOSE" = 1 ]; then
    printf '    %s+ %s%s\n' "$C_DIM" "$(_kit_display "$@")" "$C_RESET" >&2
  fi
  "$@"
}

run_sudo() { run_cmd sudo "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date +%Y%m%d%H%M%S; }

# ---------------------------------------------------------------- files

# file_same SRC DEST: DEST exists with exactly SRC's content.
file_same() { [ -f "$2" ] && cmp -s "$1" "$2"; }

# install_file SRC DEST [MODE]: copy as root if the content differs, backing up the old file.
install_file() {
  local src=$1 dest=$2 mode=${3:-644}
  if file_same "$src" "$dest"; then
    info "$dest is already up to date"
    return 0
  fi
  if [ -e "$dest" ]; then
    run_sudo cp -p "$dest" "$dest.bak.$(timestamp)"
  fi
  run_sudo mkdir -p "$(dirname "$dest")"
  run_sudo install -m "$mode" "$src" "$dest"
}

# write_file DEST [MODE] <<EOF ... EOF: like install_file, with the content on stdin.
# Never use it for secrets.
write_file() {
  local dest=$1 mode=${2:-644} tmp rc=0
  tmp=$(mktemp)
  cat >"$tmp"
  if [ "$KIT_DRY_RUN" = 1 ] && ! file_same "$tmp" "$dest"; then
    info "would write $dest:"
    sed 's/^/        /' "$tmp"
  fi
  install_file "$tmp" "$dest" "$mode" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

# ---------------------------------------------------------------- prompts (always /dev/tty)

has_tty() {
  [ "${KIT_NO_TTY:-0}" != 1 ] || return 1
  { : </dev/tty; } 2>/dev/null
}

# ask QUESTION [y|n]: y/n prompt on the terminal. No terminal → "no".
ask() {
  local q=$1 def=${2:-n} hint reply=
  if ! has_tty; then
    warn "$q → no (there's no terminal to ask on)"
    return 1
  fi
  case $def in y) hint='[Y/n]' ;; *) hint='[y/N]' ;; esac
  printf '    %s %s ' "$q" "$hint" >/dev/tty
  IFS= read -r reply </dev/tty || reply=
  [ -n "$reply" ] || reply=$def
  case $reply in [Yy] | [Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# confirm QUESTION [default]: --yes answers yes.
confirm() {
  if [ "$KIT_YES" = 1 ]; then
    info "$1 yes (--yes)"
    return 0
  fi
  ask "$@"
}

# confirm_always QUESTION [default]: for safety questions and reboots; --yes doesn't answer it.
confirm_always() { ask "$@"; }

# read_secret VAR PROMPT: read without echo from the terminal into VAR.
read_secret() {
  local __kit_var=$1 __kit_prompt=$2 __kit_val=
  has_tty || return 1
  printf '    %s: ' "$__kit_prompt" >/dev/tty
  IFS= read -rs __kit_val </dev/tty || return 1
  printf '\n' >/dev/tty
  printf -v "$__kit_var" '%s' "$__kit_val"
}

maybe_reboot() {
  if confirm_always "${1:-Reboot now?}"; then
    run_sudo systemctl reboot
  else
    info "Not rebooting. Reboot later with: sudo reboot"
  fi
}

# ---------------------------------------------------------------- privileges

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Don't run kit as root. Run it as your normal user; it uses sudo when needed." 2
  fi
}

# ensure_sudo: ask for the sudo password once and keep it fresh while kit runs.
ensure_sudo() {
  [ "$KIT_DRY_RUN" != 1 ] || return 0
  [ "${KIT_SKIP_SUDO:-0}" != 1 ] || return 0
  [ -z "${KIT_SUDO_READY:-}" ] || return 0
  have sudo || die "sudo is required"
  sudo -v || die "sudo failed"
  (while kill -0 "$$" 2>/dev/null; do
    sudo -n true 2>/dev/null
    sleep 50
  done) </dev/null >/dev/null 2>&1 &
  export KIT_SUDO_READY=1
}

# ---------------------------------------------------------------- system

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [ "$(os_release_value ID)" = ubuntu ]; then echo ubuntu; else echo linux; fi
      ;;
    *) echo unknown ;;
  esac
}

# os_release_value KEY: a value from /etc/os-release, unquoted.
os_release_value() {
  local file=${KIT_OS_RELEASE:-/etc/os-release}
  [ -r "$file" ] || return 0
  sed -n "s/^$1=//p" "$file" | head -n 1 | sed 's/^"//; s/"$//'
}

is_ssh_session() { [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; }

current_hostname() {
  if [ -n "${KIT_HOSTNAME:-}" ]; then
    printf '%s\n' "$KIT_HOSTNAME"
  else
    hostname -s 2>/dev/null || hostname
  fi | tr '[:upper:]' '[:lower:]'
}

# sha256_of FILE: the file's SHA-256 (sha256sum on Linux, shasum on macOS).
sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
