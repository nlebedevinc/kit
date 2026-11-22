#!/usr/bin/env bash
# beast bootstrap:
#
#   curl -fsSL https://raw.githubusercontent.com/nlebedevinc/beast/main/install.sh | bash
#
# Installs git and curl if missing, clones (or fast-forwards) this repo into
# ~/.local/share/beast, links ~/.local/bin/beast, then runs `beast install` with
# the arguments given here (e.g. `| bash -s -- --dry-run`).
#
# Environment: BEAST_REPO (owner/name, URL or path), BEAST_REF (branch), BEAST_PATH.
#
# Everything is inside main(), called on the last line, so a partial download runs nothing.

main() {
  set -euo pipefail

  local repo=${BEAST_REPO:-nlebedevinc/beast}
  local ref=${BEAST_REF:-main}
  local path=${BEAST_PATH:-}
  local bindir="$HOME/.local/bin"
  local url self_dir='' local_checkout=0 missing='' noninteractive=${BEAST_NONINTERACTIVE:-0} a

  step() { printf '==> %s\n' "$*" >&2; }
  fail() {
    printf 'beast install: %s\n' "$*" >&2
    exit "${2:-1}"
  }

  [ "$(id -u)" -ne 0 ] || fail "run this as your normal user, not root (beast uses sudo when it needs to)"
  for a in "$@"; do [ "$a" != --non-interactive ] || noninteractive=1; done

  # Run from a checkout (git clone … && ./install.sh)? Then use that checkout.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi
  if [ -z "$path" ] && [ -n "$self_dir" ] && [ -f "$self_dir/bin/beast" ]; then
    path=$self_dir
    local_checkout=1
  fi
  [ -n "$path" ] || path="$HOME/.local/share/beast"

  # 1. git and curl.
  command -v git >/dev/null 2>&1 || missing="$missing git"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  if [ -n "$missing" ]; then
    command -v apt-get >/dev/null 2>&1 || fail "please install:$missing, then run this again"
    command -v sudo >/dev/null 2>&1 || fail "sudo is required"
    if [ "$noninteractive" = 1 ] || ! { : </dev/tty; } 2>/dev/null; then
      sudo -n true 2>/dev/null || fail "sudo needs a password and there's no terminal. Run \`sudo -v\` in this session first, or connect with \`ssh -t\`." 5
    fi
    step "Installing$missing"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    # shellcheck disable=SC2086  # package list
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing >/dev/null
  fi

  # 2. The repository.
  if [ "$local_checkout" = 1 ]; then
    step "Using the checkout in $path"
  elif [ -d "$path/.git" ]; then
    [ -z "$(git -C "$path" status --porcelain)" ] ||
      fail "$path has local changes. Commit or stash them, then run this again."
    step "Updating $path ($ref)"
    git -C "$path" fetch --quiet origin "$ref"
    git -C "$path" checkout --quiet "$ref"
    git -C "$path" merge --quiet --ff-only "origin/$ref" ||
      fail "can't fast-forward $path to origin/$ref. Sort it out with git, then run this again."
  elif [ -e "$path" ]; then
    fail "$path exists but isn't a git checkout. Move it away, then run this again."
  else
    case $repo in
      *://* | /* | ./* | git@*) url=$repo ;;
      *) url="https://github.com/$repo.git" ;;
    esac
    step "Downloading beast into $path"
    mkdir -p "$(dirname "$path")"
    git clone --quiet --branch "$ref" "$url" "$path"
  fi

  # 3. The beast command.
  mkdir -p "$bindir"
  ln -sfn "$path/bin/beast" "$bindir/beast"
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) step "Linked $bindir/beast (on your PATH from your next login; until then: ~/.local/bin/beast)" ;;
  esac

  # 4. Hand off. Prompts must read the keyboard, not this piped script.
  step "Running: beast install $*"
  if [ "$noninteractive" != 1 ] && { : </dev/tty; } 2>/dev/null; then
    exec bash "$path/bin/beast" install "$@" </dev/tty
  fi
  exec bash "$path/bin/beast" install "$@"
}

main "$@"
