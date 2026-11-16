# kit: requirements

> **Source of truth.** This file replaces `docs/hosts/beast/ORIGINAL-SPEC.md` (kept for history).
> What gets installed on `beast` comes from `docs/hosts/beast/SETUP-LOG.md`, a record of a real, working setup.
> Automate exactly that. Don't add tools or steps that aren't in a host's setup log, except the Phase 2 items in §12.

---

## 1. Goal

`kit` is a personal machine-setup tool: a repository plus a CLI that turns a fresh OS install into a known, documented state, one **host profile** per machine. Its first host is **`beast`**, the headless Ubuntu GPU server. More hosts (e.g. the MacBook) will be added later.

**Starting point:** a fresh, stock install of the host's OS. For `beast` that's **Ubuntu Desktop** (24.04 or 26.04), right after the first login, with network access and a user who can `sudo`. No custom ISO, no preinstalled tools beyond what the stock image ships. Ubuntu Desktop 24.04 doesn't ship `curl` or `git`, so neither may be assumed before the bootstrap installs them.

One-line install (Tailscale/Omarchy style):

```bash
curl -fsSL https://raw.githubusercontent.com/<github-user>/kit/main/install.sh | bash -s -- --host beast
# fresh Ubuntu without curl:
wget -qO- https://raw.githubusercontent.com/<github-user>/kit/main/install.sh | bash -s -- --host beast
```

Or read first:

```bash
git clone https://github.com/<github-user>/kit.git ~/.local/share/kit
~/.local/share/kit/install.sh
```

The curl command **is** the installation: nothing has to be installed or downloaded by hand first. It sets up the machine in one go; the `kit` command it leaves behind is for re-runs, `kit doctor`, `kit update` and `kit lights`.

### 1.1 How the one-liner works (`install.sh`)

Modeled on Omarchy's original `boot.sh` (clone to `~/.local/share/<name>`, then hand off to the real installer; Omarchy retired its online installer in June 2026 in favor of an ISO, but the pattern is the reference) plus Tailscale's truncation guard.

1. **Truncation guard:** the whole script is inside `main() { … }`, and the last line is `main "$@"`. If the download is cut off, nothing runs.
2. **Preconditions:** refuse root; detect the OS. The bootstrap itself must not need `curl` (it may have been fetched with `wget`).
3. **Ensure git and curl:** a fresh Ubuntu Desktop lacks them, so `sudo apt-get update && sudo apt-get install -y git curl` for whichever is missing (macOS later: Xcode command line tools). Later modules (e.g. tailscale) may then rely on `curl`.
4. **Get the repo** into `KIT_PATH` (default `~/.local/share/kit`) from `KIT_REPO` (default `<github-user>/kit`) at `KIT_REF` (default `main`):
   - not there → `git clone --branch "$KIT_REF"`;
   - already a clean clone → `git fetch` and fast-forward to `KIT_REF`;
   - local changes → stop and say so (unlike Omarchy, never `rm -rf` an existing clone).
5. **Link the CLI:** `~/.local/bin/kit` → `$KIT_PATH/bin/kit`; add `~/.local/bin` to `PATH` for this run and tell the user if their shell doesn't include it.
6. **Hand off:** `exec "$KIT_PATH/bin/kit" install "$@" </dev/tty`, so all flags pass through (`--host`, `--dry-run`, `--yes`) and prompts read the keyboard, not the piped script. With no TTY (CI), run without the redirect; prompts then fail safe or need `--yes`.
7. **Re-running the one-liner is safe:** it updates the clone and re-runs `kit install`, which is idempotent.

Environment overrides: `KIT_REPO`, `KIT_REF`, `KIT_PATH`, plus `KIT_HOST` and `TAILSCALE_AUTHKEY`, e.g.
`curl -fsSL …/install.sh | KIT_REF=dev bash -s -- --host beast --dry-run`.

`--dry-run` is passed to `kit install`. The bootstrap itself still installs git/curl, clones the repo and links the command, since kit can't read its modules otherwise; nothing else changes.

Later, optional: a short URL (e.g. a custom domain that redirects to the raw GitHub file).

### Non-goals

- Firmware (BIOS), disk partitioning, the OS installer itself. Manual; documented per host in `docs/hosts/<host>/manual-steps.md` (for `beast`: from SETUP-LOG §1–2).
- Anything not in a host's setup log (see §12 for the only planned additions).
- Managing machines remotely (kit runs **on** the machine it sets up).

---

## 2. Principles

1. **Idempotent:** every module can run repeatedly; a second run changes nothing and reports "already done".
2. **Modular:** each step is a separate module; run all of a host's modules or pick some (`kit install tailscale ssh`).
3. **Safe by default:** never lock the user out (§8).
4. **Transparent:** print what each step does; support `--dry-run` everywhere.
5. **Normal user:** runs as a normal user and calls `sudo` where needed; refuses to run as root.
6. **Configurable, not hard-coded:** machine-specific values live in the host profile, overridable per user (§6).
7. **Pinned downloads:** third-party binaries use a pinned version, HTTPS URL and **SHA-256** check.
8. **Bash only:** `#!/usr/bin/env bash`, `set -euo pipefail`, passes `shellcheck`.
9. **Portable core:** `bin/kit`, `install.sh`, `lib/` and `modules/common/` must run on **bash 3.2** (macOS default): no associative arrays, `mapfile`, `${var,,}`, `declare -n`, `&>>`. OS-specific modules may assume their OS's bash.
10. **Interactive even when piped:** every prompt reads from `/dev/tty`, never stdin (stdin is the script under `curl | bash`). With no TTY and no `--yes`, prompts fail safe (answer "no").

---

## 3. Repository layout

```
kit/
├── install.sh                    # bootstrap: clone/update repo, link CLI, run `kit install`
├── bin/
│   └── kit                       # the CLI (symlinked to ~/.local/bin/kit)
├── lib/
│   ├── common.sh                 # logging, run_cmd/dry-run, sudo, prompts (/dev/tty), OS detection
│   ├── ubuntu.sh                 # apt helpers
│   ├── config.sh                 # host resolution + config loading (§6)
│   ├── modules.sh                # module discovery, loading and the contract (§5)
│   └── templates/kit.conf        # starting ~/.config/kit/kit.conf
├── modules/
│   ├── common/                   # any OS (Phase 2: tmux, neovim, dotfiles links)
│   ├── ubuntu/
│   │   ├── preflight.sh
│   │   ├── base-packages.sh
│   │   ├── nvidia.sh
│   │   ├── tailscale.sh
│   │   ├── ssh.sh
│   │   ├── wifi.sh
│   │   ├── headless.sh
│   │   └── openrgb.sh
│   └── macos/                    # later
├── hosts/
│   └── beast/
│       ├── host.conf             # module list + settings for this machine (§6)
│       ├── modules/
│       │   └── lights.sh         # host-only module
│       ├── commands/
│       │   └── lights            # host-only CLI command → `kit lights …` (§10)
│       └── files/
│           ├── ssh/99-hardening.conf
│           ├── networkmanager/wifi-powersave-off.conf
│           ├── modules-load/i2c.conf
│           └── systemd/kit-lights-off.service
├── dotfiles/                     # Phase 2
├── docs/
│   └── hosts/beast/
│       ├── SETUP-LOG.md          # unchanged
│       ├── ORIGINAL-SPEC.md      # unchanged, historical
│       ├── manual-steps.md       # from SETUP-LOG §1–2
│       └── troubleshooting.md    # from SETUP-LOG §9
├── tests/                        # §11
├── .github/workflows/ci.yml
├── SPEC.md                       # this file
├── CLAUDE.md
├── README.md
├── ROADMAP.md
└── LICENSE                       # MIT
```

**Module resolution order** for a name like `ssh`: `hosts/<host>/modules/` → `modules/<os>/` → `modules/common/`. A host can override a shared module by providing one with the same name.

---

## 4. The `kit` CLI

```
kit [global flags] <command> [args]
```

| Command | What it does |
|---|---|
| `kit install` | Run all of the host's modules in `KIT_MODULES` order (confirms before risky steps) |
| `kit install <module>…` | Run specific modules, in the given order, e.g. `kit install tailscale ssh` |
| `kit list` | Modules for this host with status: ✅ applied / ⬜ not applied / ⏭ skipped (not applicable) |
| `kit doctor` | Run every module's `verify` plus host checks; ✅/❌ table with one-line fix hints; exit non-zero if any ❌ |
| `kit update` | `git pull --ff-only` the repo, then `kit install` |
| `kit uninstall <module>` | Revert a module (required for `openrgb` and `lights`; others say "not supported") |
| `kit hosts` | List available host profiles and which one is active |
| `kit config` | Print the effective config (host defaults + user overrides), secrets never shown |
| `kit gui on\|off\|start\|stop` | Ubuntu: `set-default graphical.target` / `multi-user.target`, or `start/stop gdm` |
| `kit <host-command> …` | Commands from `hosts/<host>/commands/`, e.g. `kit lights off` |
| `kit help [command]`, `kit version` | Help and version (git describe) |

**Global flags:** `--host NAME`, `--dry-run`, `--yes` (skip confirmations; never skips safety gates), `--verbose`, `--fix` (allow repair actions, e.g. NVIDIA driver install), `--no-color`.

**CLI behavior:**
- Unknown command or module → error, list valid ones, exit 2.
- Exit codes: `0` ok, `1` a step failed, `2` usage error, `3` blocked by a safety gate.
- Output: a header per module (`==> ssh: Harden SSH (key-only login)`), then `already done` / `applied` / `skipped: <reason>` / `failed: <reason>`, and a summary at the end.
- Colors only on a TTY and when `NO_COLOR` is unset.
- Bash completion for commands, modules and hosts (`kit completion bash`), nice-to-have.

---

## 5. Module contract

Each module is a file that defines these functions; the CLI sources it in a subshell and calls them:

```bash
describe()    # one-line description (required)
applies()     # exit 0 if relevant here (OS, hardware, connection type). Default: yes
check()       # exit 0 if already applied (idempotency + `kit list`) (required)
apply()       # perform the step (required); must honor KIT_DRY_RUN via lib `run`
verify()      # post-check for `kit doctor`; default: check
uninstall()   # optional
```

- All state-changing commands go through `run_cmd` / `run_sudo` from `lib/common.sh` so `--dry-run` prints instead of executing. (Not `run`: bats owns that name.)
- Return codes from `apply`: `0` ok, `$KIT_BLOCKED` (3) stopped by a safety gate, `$KIT_SKIPPED` (5) declined by the user or waiting on a reboot, anything else failed.
- Optional `update()` runs during `kit update` (e.g. `apt full-upgrade` in base-packages).
- Each call runs in a fresh bash process (`kit __module NAME FUNC`), so `set -e` works inside module functions even though the CLI tests their exit codes.
- `kit install` flow per module: `applies` → no: skip; `check` → yes: "already done"; else `apply`, then `verify`.
- Modules never call `exit` directly; they `return` non-zero with a message.

---

## 6. Hosts and configuration

**Host selection:** `--host NAME` → `KIT_HOST` env → `KIT_HOST=` in the user config → `hostname -s` if `hosts/<that>/` exists → otherwise list hosts and ask (or fail with exit 2 when non-interactive).

**Config layers** (later wins):
1. `hosts/<host>/host.conf`: in the repo, defaults for that machine. No secrets.
2. `~/.config/kit/kit.conf`: per-user overrides; created (commented-out template) on first run.
3. Environment variables for one-off overrides and secrets (`TAILSCALE_AUTHKEY`).

Config files are plain `KEY=value` bash, sourced; values with spaces are quoted.

**System-level config for boot services:** anything a root/boot-time unit needs (the lights mapping) is written to `/etc/kit/<name>.conf` by the module that installs the unit. Units must not read `$HOME`.

**`hosts/beast/host.conf` (defaults matching this machine):**

```bash
KIT_OS=ubuntu
KIT_MODULES="preflight base-packages nvidia tailscale ssh wifi headless openrgb lights"

HOST_NAME=beast
HOST_USER=me
WIFI_CONNECTION=""                 # empty: auto-detect the active Wi-Fi connection

BASE_PACKAGES="openssh-server build-essential git curl tmux htop btop nvtop lm-sensors"

OPENRGB_VERSION=1.1
OPENRGB_URL=https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_1.1/OpenRGB_1.1_x86_64_8e16de2.AppImage
OPENRGB_SHA256=d556c2273b0ef863dbee7ffdb438304b382add5d685c93c60758b42de3b0268d   # see §13
OPENRGB_BIN=/usr/local/bin/openrgb

LIGHTS_BOOT=off                    # off | hardware
LIGHTS_RAM_DEVICES="ENE DRAM"      # every device with this name: RAM sticks
LIGHTS_GPU_DEVICE="GeForce"
LIGHTS_MB_DEVICE="MSI MYSTIC LIGHT"
LIGHTS_MB_ZONES="0 1 2 3"          # JAF, JARGB 1, JARGB 2, JARGB 3
LIGHTS_MB_ZONE_SIZE=120
LIGHTS_ON_RAM_MODE=Rainbow
LIGHTS_ON_COLOR=FFFFFF             # GPU + motherboard color for `lights on`
```

---

## 7. Modules for host `beast` (each maps to a section of SETUP-LOG.md)

### preflight
Split in two so the checks run on every pass while a second run still reports "already done":
- **Core checks in `bin/kit`, before every `kit install`:** refuse root; `sudo -v` once and keep it alive; fail if the OS doesn't match `KIT_OS` (warn only under `--dry-run`); warn but continue if Ubuntu isn't 24.04 or 26.04; record `KIT_SESSION=ssh|local` (`$SSH_CONNECTION`/`$SSH_TTY`) for the safety gates; warn (don't change) if the hostname differs from `HOST_NAME`.
- **The `preflight` module:** creates `~/.config/kit/kit.conf` from `lib/templates/kit.conf` if missing; its `verify` reports OS version, hostname and config for `kit doctor`.

### base-packages (log §3)
- `check`: every package in `BASE_PACKAGES` is installed (`dpkg-query`).
- `apply`: `apt update`, `apt full-upgrade -y`, `apt install -y $BASE_PACKAGES`.
- Upgrades on later runs happen through `kit update`, not on every `install` (otherwise a second run is never "already done").
- If `/var/run/reboot-required` exists afterwards, say so (don't reboot).

### nvidia (log §4)
- `applies`: an NVIDIA GPU is present (`lspci`); otherwise skip.
- Verify only: `nvidia-smi` works; report driver version, GPU name and memory.
- On failure, print guidance (`sudo ubuntu-drivers install`, then reboot) and fail. Only with `--fix`: run `ubuntu-drivers install` and ask about a reboot.
- `nvidia-persistenced` is a static unit, so don't try to enable it (log §4).

### tailscale (log §5.1)
- Install with the official script (`https://tailscale.com/install.sh`) if `tailscale` is missing.
- `sudo tailscale up`; if `TAILSCALE_AUTHKEY` is set, pass `--authkey` (never printed, even with `--verbose`/`--dry-run`).
- Afterwards remind the user to **disable key expiry** for this machine in the admin console.

### ssh (log §5.2–5.3)
- Ensure `openssh-server` is installed and `ssh.socket` is enabled (Ubuntu 24.04+ socket activation; `ssh.service` showing `disabled` is expected).
- Install `files/ssh/99-hardening.conf` into `/etc/ssh/sshd_config.d/`, validate with `sshd -t`, restart `ssh`; on validation failure restore the previous drop-in (or remove it) and fail.
- In `sshd_config.d` the **first** file that sets a value wins, so another file (e.g. `50-cloud-init.conf`) can override `99-hardening.conf`. `check`/`verify` use the effective values from `sshd -T` and name any overriding file.
- Create `/run/sshd` if missing before `sshd -t`/`-T` (socket activation only creates it on the first connection).
- **Safety gate** (§8.1).
- Print client instructions: `ssh-copy-id <user>@<host>` **from the client**; answer `n` if `ssh-keygen` offers to overwrite an existing key.

### wifi (log §6.1)
- `applies`: the active connection is Wi-Fi (skip if Ethernet).
- Connection: `WIFI_CONNECTION` or the active Wi-Fi connection.
- Make it system-wide: `connection.permissions ""`, `802-11-wireless-security.psk-flags 0`, `connection.autoconnect yes`.
- If the password was agent-owned (psk-flags ≠ 0, WPA/WPA3 personal only), prompt twice with `read -s` from `/dev/tty` **before changing anything**, then save `psk-flags 0` and the password together through `nmcli connection edit` on **stdin** (never argv, so it's not in `ps` or sudo's log). Never log, echo or store it elsewhere. Open networks skip this.
- Install `files/networkmanager/wifi-powersave-off.conf`.
- Restarting NetworkManager can drop the SSH session the script runs in: warn, confirm, then restart it in a detached unit (`systemd-run --on-active=2 systemctl restart NetworkManager`) so the restart finishes even if the session dies, and tell the user to reconnect.

### headless (log §6.2–6.3)
- `systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- **Safety gate** (§8.2) and an explicit confirmation, then `systemctl set-default multi-user.target`.
- Ask before rebooting; never reboot automatically.

### openrgb (log §8.2–8.3)
- `applies`: always on this host (it's in the host's module list); if no devices are detected later, `verify` reports it.
- Install `files/modules-load/i2c.conf`; `modprobe -a i2c-dev i2c-i801` (**`-a` is required**, otherwise only the first module loads).
- `apt install -y libfuse2t64 libopengl0`.
- Remove the distro `openrgb` package if installed (too old for the MSI controller).
- Download `OPENRGB_URL` to a temp dir, verify `OPENRGB_SHA256` (abort on mismatch), `install -m 755` to `OPENRGB_BIN`.
- `check`: `OPENRGB_BIN` exists **and** its SHA-256 matches (so a version bump in the config re-installs).
- Udev rules: `openrgb --generate-udev-rules /etc/udev/rules.d/60-openrgb.rules`, then `udevadm control --reload-rules && udevadm trigger`.
- `uninstall`: remove the binary, udev rules and `i2c.conf`.

### lights (host module, log §8.4–8.6)
- Write `/etc/kit/lights.conf` from the `LIGHTS_*` and `OPENRGB_BIN` settings.
- Install the lights command to `/usr/local/bin/kit-lights` (a copy, so the boot unit doesn't depend on the user's home) and `files/systemd/kit-lights-off.service` (`ExecStart=/usr/local/bin/kit-lights off`, `After=systemd-modules-load.service`, `WantedBy=multi-user.target`).
- Enable the unit only if `LIGHTS_BOOT=off`; with `LIGHTS_BOOT=hardware`, keep it disabled so the motherboard's stored rainbow survives reboots (log §8.6).
- Migration: if the old hand-made `/usr/local/bin/lights` / `lights-off.service` from the setup log exist, offer to disable and remove them.
- `uninstall`: disable and remove the unit, `/usr/local/bin/kit-lights` and `/etc/kit/lights.conf`.

---

## 8. Safety rules (enforced in code; `--yes` never bypasses them)

1. **SSH:** never disable password login unless `~/.ssh/authorized_keys` exists and contains a key. If running locally (not over SSH), also require confirmation that `ssh <user>@<host>` with a key was tested from the client. Validate with `sshd -t` before restarting; roll back the drop-in on failure.
2. **Before headless:** Tailscale is up (`tailscale status` succeeds), `ssh.socket` is enabled, and sleep is masked. Running locally → remind the user to test `ssh <user>@<host>` from the client first.
3. **No automatic reboots** or network restarts without a confirmation.
4. **Secrets** (Wi-Fi password, Tailscale auth key) are never logged, echoed, put in the process list where avoidable, or written to the repo or config.
5. **Downloads:** HTTPS only; SHA-256 verified for pinned binaries; abort on mismatch. The official Tailscale install script is the one documented exception (unpinned, as in the setup log).
6. **Files kit replaces** are backed up first (`*.bak.<timestamp>`).

---

## 9. `kit doctor` checks (host `beast`)

Each prints ✅/❌ with a one-line fix hint.

| Check | Command | Pass when |
|---|---|---|
| OS | `/etc/os-release` | Ubuntu 24.04 or 26.04 |
| GPU | `nvidia-smi --query-gpu=name,driver_version,memory.used --format=csv,noheader` | succeeds |
| Boot target | `systemctl get-default` | `multi-user.target` |
| Sleep | `systemctl is-enabled sleep.target` | `masked` |
| SSH | `systemctl is-enabled ssh.socket` | `enabled` |
| SSH hardening | `sudo sshd -T` | `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no` |
| Tailscale | `tailscale status` | succeeds |
| Wi-Fi (if used) | `nmcli -g connection.permissions,802-11-wireless-security.psk-flags,connection.autoconnect connection show "<name>"` | empty / `0` / `yes` |
| OpenRGB | `openrgb --noautoconnect -l` | lists the configured devices |
| Lights boot unit | `systemctl is-enabled kit-lights-off.service` | matches `LIGHTS_BOOT` |
| Ghostty terminfo (info only) | `infocmp xterm-ghostty` | present, or hint: `infocmp -x xterm-ghostty \| ssh <user>@<host> -- tic -x -` on the client |

---

## 10. `kit lights` (host `beast`)

Same behavior as the script in SETUP-LOG §8.5, but driven by config. Available as `kit lights …` and, for the boot unit and convenience, `/usr/local/bin/kit-lights`. Reads `/etc/kit/lights.conf` if present, else the host config.

```
kit lights on            # LIGHTS_ON_* from the config
kit lights off
kit lights <RRGGBB>      # everything one color
kit lights status        # detected devices and the configured mapping
kit lights detect        # detect devices and print/update the mapping
kit lights --help
```

**Hard requirements (from the setup log):**
1. Resolve device indices **by name** from `openrgb --noautoconnect -l` at runtime; indices can change.
2. One `openrgb` call per action where possible (each call rescans hardware, a few seconds).
3. MSI device: always `-m Direct`, and put `-z N -sz SIZE` **before** `-c COLOR` in the same call, for every zone. Sizes don't carry over between calls.
4. RAM off: `-m Off`. GPU off: `-m Direct -c 000000`, then `-m Static -c 000000 -b 0` as a fallback (no `Off` mode).
5. Always pass `--noautoconnect`.
6. Works as a normal user when the udev rules are installed; otherwise needs root (say so on permission errors).
7. `--help` states that `on` can't restore the motherboard's built-in rainbow (Direct only) and points to the power-cycle method in `docs/hosts/beast/troubleshooting.md`.
8. Input validation: colors must match `^[0-9A-Fa-f]{6}$`.

---

## 11. Testing

- **Lint:** `shellcheck` on every script (CI on GitHub Actions).
- **Unit tests (`bats`):** `lib/` (logging, dry-run, prompts with no TTY, config layering, host resolution), CLI argument parsing and exit codes, module loading/resolution, and `kit lights` command construction. Mock `openrgb` with a stub that prints the device list from SETUP-LOG §8.1 and records its arguments; also a stub with reordered indices to prove name-based resolution.
- **bash 3.2:** run the core tests under macOS `/bin/bash` (CI `macos-latest` job).
- **Bootstrap tests:** a truncated copy of `install.sh` runs nothing; an existing clean clone is fast-forwarded; a clone with local changes stops the install; flags reach `kit install` unchanged.
- **Container test:** `cat install.sh | bash -s -- --dry-run --yes --host beast` (the real piped path, with `KIT_REPO` pointing at the checkout under test) in a stock `ubuntu:24.04` image with **no git or curl preinstalled**, to prove the fresh-install path. in `ubuntu:24.04` in CI; hardware modules (`nvidia`, `openrgb`, `lights`) detect the missing hardware and skip cleanly.
- **Real-machine acceptance:** on `beast`, `kit doctor` is all green and a second `kit install` reports every module "already done".

---

## 12. Phase 2 (planned; opt-in; record in ROADMAP.md)

- **tmux** (`modules/common/tmux.sh`): `dotfiles/tmux/tmux.conf` → `~/.config/tmux/tmux.conf`; theme **Rosé Pine** (`rose-pine/tmux`) via TPM.
- **neovim** (`modules/common/neovim.sh`): pinned official release binary with checksum; `dotfiles/nvim/` → `~/.config/nvim`; **Rosé Pine** (`rose-pine/neovim`), `lazy.nvim`.
- **macbook host** (`hosts/macbook/`, `modules/macos/`): Homebrew packages, Ghostty config incl. `shell-integration-features = ssh-env,ssh-terminfo` (SETUP-LOG §7), shared dotfiles. Needs its own setup log first.

Symlinks back up existing files (`*.bak.<timestamp>`) before replacing them.

---

## 13. Open items

- [ ] **GitHub username** for the install URL (placeholder `<github-user>`).
- [ ] **OpenRGB SHA-256:** the value above was computed from the locally downloaded AppImage. Cross-check it against the Codeberg release page before relying on it.
- [ ] **LICENSE:** copyright holder name for the MIT license.
- [ ] Confirm the SETUP-LOG §10 items on the real machine (Ubuntu version, `sshd -T`, key expiry, current `lights-off.service` state).

---

## 14. README outline

1. What kit is (one paragraph) and the hosts it supports (with `beast` hardware table)
2. Quick install (one-liner, `--host`, clone method)
3. Manual steps first (per host)
4. CLI usage (`kit` commands, `kit lights`)
5. Modules table per host
6. Safety notes (SSH keys before hardening; headless confirmation)
7. Adding a new host
8. Troubleshooting and roadmap links
