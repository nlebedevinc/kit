# shellcheck shell=bash
# Shared test setup: a throwaway HOME and a fixture kit root with fake modules.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
TEST_BASH=${KIT_TEST_BASH:-bash}

kit_setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
  mkdir -p "$HOME"
  export KIT_NO_TTY=1 NO_COLOR=1 KIT_SKIP_SUDO=1 KIT_HOSTNAME=some-other-machine
  unset KIT_HOST KIT_DRY_RUN KIT_YES KIT_VERBOSE KIT_FIX SSH_CONNECTION SSH_TTY TAILSCALE_AUTHKEY

  ROOT="$TMP/kit"
  mkdir -p "$ROOT"
  cp -R "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$ROOT/"
  export KIT_ROOT="$ROOT"

  STATE="$TMP/state"
  mkdir -p "$STATE"
  export STATE

  make_host testbox 'KIT_MODULES="alpha beta"'
}

kit_teardown() { rm -rf "$TMP"; }

# make_host NAME [EXTRA_CONF_LINES]
make_host() {
  mkdir -p "$ROOT/hosts/$1/modules" "$ROOT/hosts/$1/commands"
  cat >"$ROOT/hosts/$1/host.conf" <<EOF
KIT_OS=\$(detect_os)
HOST_NAME=$1
GREETING=hello
${2:-}
EOF
}

# make_module NAME [BODY] [HOST]: a fake host module.
# The default body applies by touching $STATE/NAME.
make_module() {
  local name=$1 host=${3:-testbox}
  local body=${2:-"describe() { echo \"Module $name\"; }
check() { [ -f \"\$STATE/$name\" ]; }
apply() { run_cmd touch \"\$STATE/$name\"; }"}
  printf '%s\n' "$body" >"$ROOT/hosts/$host/modules/$name.sh"
}

kit() { "$TEST_BASH" "$ROOT/bin/kit" "$@"; }

# Source the libraries into the test shell (unit tests of single functions).
load_libs() {
  # shellcheck source=../lib/common.sh
  . "$ROOT/lib/common.sh"
  # shellcheck source=../lib/config.sh
  . "$ROOT/lib/config.sh"
  # shellcheck source=../lib/modules.sh
  . "$ROOT/lib/modules.sh"
}
