#!/usr/bin/env bats
# install.sh: the curl | bash bootstrap.

load helpers

setup() {
  kit_setup
  # A source repo with a fake bin/kit that just records how it was called.
  SRC="$TMP/src"
  mkdir -p "$SRC/bin"
  cp "$REPO_ROOT/install.sh" "$SRC/install.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "kit-called: $*"' >"$SRC/bin/kit"
  chmod +x "$SRC/bin/kit"
  git -C "$SRC" init -q -b main
  git -C "$SRC" -c user.email=t@example.com -c user.name=t add -A
  git -C "$SRC" -c user.email=t@example.com -c user.name=t commit -qm init
  export KIT_REPO="$SRC" KIT_PATH="$TMP/clone"
}
teardown() { kit_teardown; }

piped_install() { "$TEST_BASH" -s -- "$@" <"$REPO_ROOT/install.sh"; }

@test "piped install clones, links the command and hands off all flags" {
  run piped_install --host beast --dry-run
  [ "$status" -eq 0 ]
  [ -f "$KIT_PATH/bin/kit" ]
  [ -L "$HOME/.local/bin/kit" ]
  [[ "$output" == *"kit-called: install --host beast --dry-run"* ]]
}

@test "a truncated download runs nothing" {
  local size half
  size=$(wc -c <"$REPO_ROOT/install.sh")
  half=$((size - 20))
  run "$TEST_BASH" -c "head -c $half '$REPO_ROOT/install.sh' | '$TEST_BASH' -s -- --host beast"
  [ ! -e "$KIT_PATH" ]
  [[ "$output" != *"kit-called"* ]]
}

@test "running it again fast-forwards an existing clean clone" {
  piped_install >/dev/null
  echo new >"$SRC/NEWFILE"
  git -C "$SRC" -c user.email=t@example.com -c user.name=t add -A
  git -C "$SRC" -c user.email=t@example.com -c user.name=t commit -qm more
  run piped_install
  [ "$status" -eq 0 ]
  [ -f "$KIT_PATH/NEWFILE" ]
  [[ "$output" == *"Updating kit"* ]]
}

@test "a clone with local changes stops the install" {
  piped_install >/dev/null
  echo mine >>"$KIT_PATH/bin/kit"
  run piped_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"local changes"* ]]
  [[ "$output" != *"kit-called"* ]]
}

@test "the placeholder repo gives a clear error instead of a failed clone" {
  unset KIT_REPO
  run piped_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"KIT_REPO"* ]]
}

@test "running install.sh from a checkout uses that checkout" {
  unset KIT_PATH
  run "$TEST_BASH" "$SRC/install.sh" --host beast
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using the kit checkout in $SRC"* ]]
  [[ "$output" == *"kit-called: install --host beast"* ]]
}
