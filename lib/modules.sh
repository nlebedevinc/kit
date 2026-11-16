# shellcheck shell=bash
# Module discovery and the module contract (SPEC §5).
#
# A module defines describe, check and apply, and optionally applies, verify,
# uninstall and update. Every call runs in a fresh bash process
# (`kit __module NAME FUNC`) so `set -e` works inside module functions and
# nothing leaks between modules.

# module_file NAME: host modules → OS modules → common modules.
module_file() {
  local name=$1 d
  valid_name "$name" || return 1
  for d in "$KIT_HOST_DIR/modules" "$KIT_ROOT/modules/$KIT_OS" "$KIT_ROOT/modules/common"; do
    if [ -f "$d/$name.sh" ]; then
      printf '%s\n' "$d/$name.sh"
      return 0
    fi
  done
  return 1
}

# module_call NAME FUNC: run one module function in a child process.
module_call() {
  "$BASH" "$KIT_ROOT/bin/kit" __module "$1" "$2"
}

# module_call_quiet NAME FUNC: same, output hidden unless --verbose.
module_call_quiet() {
  if [ "$KIT_VERBOSE" = 1 ]; then
    module_call "$@"
  else
    module_call "$@" >/dev/null 2>&1
  fi
}

# module_exec NAME FUNC: inside the child: load the module and call FUNC.
module_exec() {
  local name=$1 fn=$2 file
  file=$(module_file "$name") || {
    err "Unknown module: $name"
    return 2
  }
  case $fn in describe | applies | check | apply | verify | uninstall | update) ;; *)
    err "Unknown module function: $fn"
    return 2
    ;;
  esac

  # shellcheck disable=SC2034  # read by modules
  KIT_MODULE=$name

  # Defaults; the module overrides what it needs.
  applies() { return 0; }
  verify() {
    if check >/dev/null 2>&1; then
      report ok "$(describe)"
    else
      report fail "$(describe)" "kit install $KIT_MODULE"
    fi
    report_status
  }
  uninstall() {
    err "Module '$KIT_MODULE' can't be uninstalled by kit."
    return 2
  }
  update() { return 0; }

  # shellcheck source=/dev/null
  . "$file"
  "$fn"
}

# host_file REL: path of a file shipped with the host profile (hosts/<host>/files/REL).
host_file() {
  local f="$KIT_HOST_DIR/files/$1"
  [ -f "$f" ] || die "Missing file for host $KIT_HOST: files/$1"
  printf '%s\n' "$f"
}
