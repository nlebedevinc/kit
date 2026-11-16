#!/usr/bin/env bash
# kit bootstrap. Sets up this machine in one go:
#
#   curl -fsSL https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
#   wget -qO- https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
#
# Installs git/curl if missing, clones (or fast-forwards) kit into ~/.local/share/kit,
# links ~/.local/bin/kit, then runs `kit install` with the arguments given here.
#
# Environment: KIT_REPO (owner/name, URL or path), KIT_REF (branch), KIT_PATH (clone dir).
#
# Everything is inside main(), which is called on the last line, so a partial
# download runs nothing.

main() {
  set -euo pipefail

  local repo=${KIT_REPO:-nlebedevinc/kit}
  local ref=${KIT_REF:-main}
  local path=${KIT_PATH:-}
  local bindir="$HOME/.local/bin"
  local url self_dir='' local_checkout=0 missing='' bold='' reset=''

  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    bold=$'\033[1m' reset=$'\033[0m'
  fi
  step() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
  fail() {
    printf 'kit install: %s\n' "$*" >&2
    exit 1
  }

  [ "$(id -u)" -ne 0 ] || fail "run this as your normal user, not root (kit uses sudo when it needs to)"

  # Run from a checkout (git clone … && ./install.sh)? Then use that checkout.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi
  if [ -z "$path" ] && [ -n "$self_dir" ] && [ -f "$self_dir/bin/kit" ]; then
    path=$self_dir
    local_checkout=1
  fi
  [ -n "$path" ] || path="$HOME/.local/share/kit"

  # 1. git and curl: a fresh Ubuntu Desktop has neither.
  command -v git >/dev/null 2>&1 || missing="$missing git"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  if [ -n "$missing" ]; then
    case "$(uname -s)" in
      Linux)
        command -v apt-get >/dev/null 2>&1 || fail "please install:$missing (no apt-get here), then run this again"
        command -v sudo >/dev/null 2>&1 || fail "sudo is required"
        step "Installing$missing"
        sudo apt-get update
        # shellcheck disable=SC2086  # package list
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y $missing
        ;;
      Darwin)
        xcode-select --install >/dev/null 2>&1 || true
        fail "git isn't installed. Finish the Xcode Command Line Tools install that just opened, then run this again."
        ;;
      *) fail "please install:$missing, then run this again" ;;
    esac
  fi

  # 2. The repository.
  if [ "$local_checkout" = 1 ]; then
    step "Using the kit checkout in $path"
  elif [ -d "$path/.git" ]; then
    if [ -n "$(git -C "$path" status --porcelain)" ]; then
      fail "$path has local changes. Commit or stash them (or move the folder), then run this again."
    fi
    step "Updating kit in $path ($ref)"
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
    step "Downloading kit into $path"
    mkdir -p "$(dirname "$path")"
    git clone --quiet --branch "$ref" "$url" "$path"
  fi

  # 3. The kit command.
  mkdir -p "$bindir"
  ln -sfn "$path/bin/kit" "$bindir/kit"
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *)
      export PATH="$bindir:$PATH"
      step "Linked $bindir/kit (it's on your PATH from your next login; until then use ~/.local/bin/kit)"
      ;;
  esac

  # 4. Hand off. Prompts must read the keyboard, not this piped script.
  step "Running: kit install $*"
  if [ "${KIT_NO_TTY:-0}" != 1 ] && { : </dev/tty; } 2>/dev/null; then
    exec bash "$path/bin/kit" install "$@" </dev/tty
  fi
  exec bash "$path/bin/kit" install "$@"
}

main "$@"
