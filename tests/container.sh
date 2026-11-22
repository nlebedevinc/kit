#!/usr/bin/env bash
# Runs as root inside a stock ubuntu:24.04 or ubuntu:26.04 container.
# The real `curl | bash` path on a fresh system: no git, no curl, no hardware.
#   install.sh --dry-run --yes --non-interactive --json
# Expected: exit 0, every module planned or skipped, hardware modules skipped,
# nothing changed on the system.
set -euo pipefail

: "${BEAST_REF:?set BEAST_REF to the branch under test}"

apt-get update -qq
apt-get install -y -qq sudo >/dev/null
if command -v git || command -v curl; then
  echo "FAIL: the image isn't stock (git or curl already installed)"
  exit 1
fi
useradd -m -s /bin/bash tester
echo "tester ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/tester
cp -r /src /home/tester/beast-src
chown -R tester: /home/tester/beast-src

fail() {
  echo "FAIL: $*"
  exit 1
}

rc=0
out=$(su - tester -c "cat ~/beast-src/install.sh | BEAST_REPO=\$HOME/beast-src BEAST_REF=$BEAST_REF timeout 600 bash -s -- --dry-run --yes --non-interactive --json" 2>/tmp/stderr </dev/null) || rc=$?
cat /tmp/stderr
printf '%s\n' "$out"

[ "$rc" -eq 0 ] || fail "expected exit 0, got $rc"
[ "$(printf '%s\n' "$out" | grep -c '"type":"module"')" -eq 11 ] || fail "expected 11 module events"
for m in 20-nvidia 50-wifi 70-openrgb 80-lights; do
  printf '%s\n' "$out" | grep "\"id\":\"$m\"" | grep -q '"status":"skipped"' || fail "$m should be skipped (no hardware)"
done
if printf '%s\n' "$out" | grep -q '"status":"\(failed\|applied\)"'; then fail "a dry run applied or failed something"; fi
printf '%s\n' "$out" | tail -n 1 | grep -q '"type":"summary","ok":true,"exit_code":0' || fail "bad summary"
command -v git >/dev/null || fail "the bootstrap didn't install git"
[ ! -e /home/tester/.config/beast/beast.conf ] || fail "the dry run created the config"
[ ! -e /usr/local/bin/beast-check ] || fail "the dry run installed beast-check"

su - tester -c "/home/tester/.local/bin/beast list" </dev/null
echo "OK: fresh-Ubuntu dry run behaves as expected"
