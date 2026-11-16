#!/usr/bin/env bash
# Runs as root inside a stock ubuntu:24.04 container (see .github/workflows/ci.yml).
# Proves the real `curl | bash` path on a fresh install: no git, no curl, no SSH key,
# no Tailscale login. Expected: the bootstrap installs git/curl, the dry run plans
# every module, and the two safety gates (ssh, headless) block, so exit code 3.
set -euo pipefail

: "${KIT_REF:?set KIT_REF to the branch under test}"

apt-get update -qq
apt-get install -y -qq sudo >/dev/null
if command -v git || command -v curl; then
  echo "FAIL: the image isn't stock (git or curl already installed)"
  exit 1
fi

useradd -m -s /bin/bash tester
echo "tester ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/tester
cp -r /src /home/tester/kit-src
chown -R tester: /home/tester/kit-src

rc=0
out=$(su - tester -c "cat ~/kit-src/install.sh | KIT_REPO=\$HOME/kit-src KIT_REF=$KIT_REF bash -s -- --dry-run --yes --host beast" 2>&1) || rc=$?
printf '%s\n' "$out"

fail() {
  echo "FAIL: $*"
  exit 1
}
[ "$rc" -eq 3 ] || fail "expected exit code 3 (blocked by safety gates), got $rc"
printf '%s\n' "$out" | grep -q 'Summary:.*blocked: ssh headless$' || fail "expected exactly ssh and headless to be blocked"
if printf '%s\n' "$out" | grep -q 'failed:'; then fail "a module failed"; fi
command -v git >/dev/null || fail "the bootstrap didn't install git"
command -v curl >/dev/null || fail "the bootstrap didn't install curl"

su - tester -c "/home/tester/.local/bin/kit --host beast --dry-run list"
echo "OK: fresh-Ubuntu install behaves as expected"
