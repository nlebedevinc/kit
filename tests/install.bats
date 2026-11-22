#!/usr/bin/env bats
# install.sh: the curl | bash bootstrap.

load helpers

setup() {
  beast_setup
  SRC="$TMP/src"
  mkdir -p "$SRC/bin"
  cp "$REPO_ROOT/install.sh" "$SRC/install.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "beast-called: $*"' >"$SRC/bin/beast"
  chmod +x "$SRC/bin/beast"
  git -C "$SRC" init -q -b main
  git -C "$SRC" -c user.email=t@example.com -c user.name=t add -A
  git -C "$SRC" -c user.email=t@example.com -c user.name=t commit -qm init
  export BEAST_REPO="$SRC" BEAST_PATH="$TMP/clone"
}
teardown() { beast_teardown; }

piped_install() { bash -s -- "$@" <"$REPO_ROOT/install.sh"; }

@test "piped install clones, links the command and hands off all flags" {
  run piped_install --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$BEAST_PATH/bin/beast" ]
  [ -L "$HOME/.local/bin/beast" ]
  [[ "$output" == *"beast-called: install --dry-run --non-interactive"* ]]
}

@test "a truncated download runs nothing" {
  local size
  size=$(wc -c <"$REPO_ROOT/install.sh")
  run bash -c "head -c $((size - 20)) '$REPO_ROOT/install.sh' | bash -s"
  [ ! -e "$BEAST_PATH" ]
  [[ "$output" != *"beast-called"* ]]
}

@test "running it again fast-forwards a clean clone" {
  piped_install >/dev/null 2>&1
  echo new >"$SRC/NEWFILE"
  git -C "$SRC" -c user.email=t@example.com -c user.name=t add -A
  git -C "$SRC" -c user.email=t@example.com -c user.name=t commit -qm more
  run piped_install
  [ "$status" -eq 0 ]
  [ -f "$BEAST_PATH/NEWFILE" ]
}

@test "a clone with local changes stops the install" {
  piped_install >/dev/null 2>&1
  echo mine >>"$BEAST_PATH/bin/beast"
  run piped_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"local changes"* ]]
  [[ "$output" != *"beast-called"* ]]
}

@test "running install.sh from a checkout uses that checkout" {
  unset BEAST_PATH
  run bash "$SRC/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using the checkout in $SRC"* ]]
  [[ "$output" == *"beast-called: install --dry-run"* ]]
}

@test "the default repo is github.com/nlebedevinc/beast" {
  grep -q 'local repo=${BEAST_REPO:-nlebedevinc/beast}' "$REPO_ROOT/install.sh"
}
