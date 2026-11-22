# shellcheck shell=bash
# beast output: exit codes, colors, human vs. JSON output (SPEC §8.2–8.3).
# JSON goes to stdout only; human logs go to stderr (and the install log, see common.sh).

# Exit codes shared by every command (SPEC §8.2).
# shellcheck disable=SC2034  # used by bin/beast and the modules
EXIT_OK=0 EXIT_FAIL=1 EXIT_USAGE=2 EXIT_MANUAL=3 EXIT_BLOCKED=4 EXIT_SUDO=5 EXIT_LOCKED=6

# Module return codes besides 0 (done) and 1 (failed). Unusual numbers on purpose,
# so that a failing command inside apply() (nmcli and curl use small codes) can't
# be mistaken for one of them.
# shellcheck disable=SC2034
MOD_MANUAL=73 MOD_BLOCKED=74 MOD_SKIPPED=75

BEAST_JSON=${BEAST_JSON:-0}
BEAST_NO_COLOR=${BEAST_NO_COLOR:-0}

color_init() {
  if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "$BEAST_NO_COLOR" != 1 ]; then
    C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
    C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
  else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
  fi
}
color_init

# json_str STRING: a JSON string literal (quoted and escaped).
json_str() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '"%s"' "$s"
}

# json_arr ITEM...: a JSON array of strings.
json_arr() {
  local out='' item
  for item in "$@"; do
    out="$out${out:+,}$(json_str "$item")"
  done
  printf '[%s]' "$out"
}

_status_color() {
  case $1 in
    applied | already) printf '%s' "$C_GREEN" ;;
    failed) printf '%s' "$C_RED" ;;
    blocked | manual) printf '%s' "$C_YELLOW" ;;
    *) printf '%s' "$C_DIM" ;;
  esac
}

# emit_module ID STATUS MESSAGE [ACTION...]: one module result.
# JSON: an NDJSON event on stdout. Human: a status line (and the actions) on stderr.
emit_module() {
  local id=$1 status=$2 message=$3 a
  shift 3
  if [ "$BEAST_JSON" = 1 ]; then
    printf '{"type":"module","id":%s,"status":%s,"message":%s,"actions":%s}\n' \
      "$(json_str "$id")" "$(json_str "$status")" "$(json_str "$message")" "$(json_arr "$@")"
  else
    printf '  %s%-8s%s %-18s %s\n' "$(_status_color "$status")" "$status" "$C_RESET" "$id" "$message" >&2
    for a in "$@"; do
      printf '           %s- %s%s\n' "$C_DIM" "$a" "$C_RESET" >&2
    done
  fi
}
