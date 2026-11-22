# shellcheck shell=bash
# 99-verify: install beast-check to /usr/local/bin (so it works without the repo)
# and run it. Always last; beast install fails if any health check fails.

CHECK_DEST=/usr/local/bin/beast-check

describe() { echo "Installs and runs the health check (beast-check)"; }

check() { file_same "$BEAST_ROOT/bin/beast-check" "$CHECK_DEST"; }

plan() {
  check || echo "install bin/beast-check to $CHECK_DEST"
  echo "run beast-check --json"
}

apply() {
  local out pass warn fail
  install_file "$BEAST_ROOT/bin/beast-check" "$CHECK_DEST" 755
  out="$BEAST_RUN_DIR/doctor.json"
  # The repo copy is the same file; running it keeps this working before /usr/local/bin is on PATH.
  bash "$BEAST_ROOT/bin/beast-check" --json --config "$BEAST_CONFIG" >"$out" || true
  if ! grep -q '"summary"' "$out"; then
    err "beast-check produced no result"
    return 1
  fi
  pass=$(sed -n 's/.*"summary":{"pass":\([0-9]*\),"warn":\([0-9]*\),"fail":\([0-9]*\).*/\1/p' "$out")
  warn=$(sed -n 's/.*"summary":{"pass":\([0-9]*\),"warn":\([0-9]*\),"fail":\([0-9]*\).*/\2/p' "$out")
  fail=$(sed -n 's/.*"summary":{"pass":\([0-9]*\),"warn":\([0-9]*\),"fail":\([0-9]*\).*/\3/p' "$out")
  grep -E '"status":"(warn|fail)"' "$out" | sed -n 's/.*"id":"\([^"]*\)".*"status":"\([a-z]*\)","message":"\([^"]*\)".*/    \2  \1: \3/p' >&2 || true
  module_message "$pass passed, $warn warnings, $fail failed"
  [ "$fail" -eq 0 ]
}
