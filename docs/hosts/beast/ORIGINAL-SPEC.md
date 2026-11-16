# beast: project spec for implementation

> **For Claude Code:** this spec describes the repository to build. The source of truth for *what* gets installed is [`SETUP-LOG.md`](./SETUP-LOG.md), a record of a real, working setup. Automate exactly that. Don't add tools or steps that aren't in the log, except the Phase 2 items explicitly listed below.

---

## 1. Goal

A dotfiles-style repository that turns a fresh **Ubuntu Desktop** install into the headless GPU server documented in `SETUP-LOG.md`, with a one-line installer in the style of Tailscale and Omarchy:

```bash
curl -fsSL https://raw.githubusercontent.com/<github-user>/beast/main/install.sh | bash
```

or, for people who prefer to read first:

```bash
git clone https://github.com/<github-user>/beast.git ~/.local/share/beast
~/.local/share/beast/install.sh
```

### Non-goals

- Firmware (BIOS) settings, disk partitioning and the Ubuntu installer itself. These are manual; document them in `docs/manual-steps.md` from `SETUP-LOG.md` Sections 1–2.
- Anything not in `SETUP-LOG.md` (see Phase 2 for the only planned additions).

---

## 2. Principles

1. **Idempotent:** every module can run repeatedly; a second run changes nothing and reports "already done."
2. **Modular:** each step is a separate script; users can run all of them or pick some (`beast install tailscale`).
3. **Safe by default:** never lock the user out (see Section 6).
4. **Transparent:** print what each step does; support `--dry-run`.
5. **Runs as a normal user** and calls `sudo` where needed; refuse to run as root.
6. **Configurable, not hard-coded:** hostname, username, Wi-Fi connection name, light colors and OpenRGB device mapping come from a config file, with defaults matching this machine.
7. **Pinned downloads:** third-party binaries (the OpenRGB AppImage) use a pinned version and a **SHA-256 checksum** check.
8. **Bash only:** `#!/usr/bin/env bash`, `set -euo pipefail`, passes `shellcheck`.

---

## 3. Repository layout

```
beast/
├── install.sh                  # bootstrap: clone/update repo, then run `beast install`
├── bin/
│   ├── beast                   # main CLI (installed to ~/.local/bin/beast)
│   └── lights                  # RGB control (installed to /usr/local/bin/lights)
├── modules/                    # one file per step, run in numeric order
│   ├── 00-preflight.sh
│   ├── 10-base-packages.sh
│   ├── 20-nvidia.sh
│   ├── 30-tailscale.sh
│   ├── 40-ssh.sh
│   ├── 50-wifi.sh
│   ├── 60-headless.sh
│   ├── 70-openrgb.sh
│   └── 80-lights.sh
├── lib/
│   └── common.sh               # logging, sudo helpers, idempotency helpers, config loading
├── config/
│   ├── beast.conf.example      # user settings (copied to ~/.config/beast/beast.conf)
│   ├── ssh/99-hardening.conf
│   ├── networkmanager/wifi-powersave-off.conf
│   ├── modules-load/i2c.conf
│   └── systemd/lights-off.service
├── docs/
│   ├── SETUP-LOG.md            # the provided log, unchanged
│   ├── manual-steps.md         # BIOS + dual boot + Ubuntu installer (from SETUP-LOG §1–2)
│   └── troubleshooting.md      # from SETUP-LOG §9
├── tests/                      # see Section 9
├── README.md
├── ROADMAP.md                  # Phase 2 (Section 10)
└── LICENSE                     # MIT
```

---

## 4. The `beast` CLI

| Command | What it does |
|---|---|
| `beast install` | Run all modules in order (asks for confirmation before the headless step) |
| `beast install <module>…` | Run specific modules, e.g. `beast install tailscale ssh` |
| `beast list` | List modules and whether each is applied (from each module's `check` function) |
| `beast doctor` | Run all verification checks (Section 7) and print a pass/fail table |
| `beast update` | `git pull` the repo, then re-run `beast install` (idempotent) |
| `beast gui on\|off\|start\|stop` | Desktop fallback: `set-default graphical/multi-user.target`, or `start/stop gdm` |
| `beast uninstall <module>` | Revert a module where possible (required for `openrgb` and `lights`) |
| Global flags | `--dry-run`, `--yes` (skip confirmations), `--verbose` |

**Module contract:** each `modules/NN-name.sh` defines these functions, which the CLI sources and calls:

```bash
describe()   # one-line description
check()      # exit 0 if already applied (used for idempotency and `beast list`)
apply()      # perform the step
verify()     # post-check, used by `beast doctor`
uninstall()  # optional
```

---

## 5. Modules (each maps to a section of SETUP-LOG.md)

### 00-preflight
- Refuse to run as root; require `sudo`.
- Detect Ubuntu and its version (`/etc/os-release`); warn, but continue, if it's not 24.04 or 26.04.
- Detect whether the session is over SSH (`$SSH_CONNECTION`) and record it for the safety checks.
- Load the config; create `~/.config/beast/beast.conf` from the example if missing.

### 10-base-packages (log §3)
```
apt update && apt full-upgrade -y
apt install -y openssh-server build-essential git curl tmux htop btop nvtop lm-sensors
```

### 20-nvidia (log §4)
- **Verify only** by default: `nvidia-smi` works; report driver version, GPU name and memory.
- If `nvidia-smi` fails, print guidance (`sudo ubuntu-drivers install`, then reboot) and exit non-zero. Don't install drivers automatically unless `--fix` is passed.

### 30-tailscale (log §5.1)
- Install with the official script if `tailscale` is missing.
- `sudo tailscale up`; if `TAILSCALE_AUTHKEY` is set in the environment, pass `--authkey` for unattended runs.
- Afterwards, remind the user to **disable key expiry** for this machine in the admin console. It can't be automated without an API key.

### 40-ssh (log §5.2–5.3)
- Ensure `openssh-server` is installed and `ssh.socket` is enabled.
- Install `config/ssh/99-hardening.conf` to `/etc/ssh/sshd_config.d/`, validate with `sshd -t`, restart `ssh`.
- **Safety gate** (Section 6): skip hardening, with a clear message, unless `~/.ssh/authorized_keys` contains at least one key.
- Print the client-side instructions: `ssh-copy-id <user>@<host>` from the client; answer `n` if `ssh-keygen` offers to overwrite an existing key.

### 50-wifi (log §6.1) — optional, skipped if the active connection is Ethernet
- Find the active Wi-Fi connection (or use `WIFI_CONNECTION` from the config).
- Make it system-wide: `connection.permissions ""`, `802-11-wireless-security.psk-flags 0`, `connection.autoconnect yes`.
- If the password was agent-owned, prompt for it **without echoing** (`read -s`) and set `wifi-sec.psk`. Never write it to the log or config.
- Install `config/networkmanager/wifi-powersave-off.conf`. Warn that restarting NetworkManager briefly drops SSH, then restart it.

### 60-headless (log §6.2–6.3)
- `systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- `systemctl set-default multi-user.target`
- **Safety gate** (Section 6) and an explicit confirmation before switching to `multi-user.target`.
- Ask before rebooting; never reboot automatically.

### 70-openrgb (log §8.2–8.3)
- Install `config/modules-load/i2c.conf` and run `modprobe -a i2c-dev i2c-i801`. Note: **`-a` is required** for loading two modules.
- `apt install -y libfuse2t64 libopengl0`
- Remove the distro `openrgb` package if it's installed (it's too old for the MSI controller).
- Download the pinned AppImage (version, URL and SHA-256 in the config or a constants file; default: **1.1**, `OpenRGB_1.1_x86_64_8e16de2.AppImage` from Codeberg), verify the checksum, and install it as `/usr/local/bin/openrgb`.
- Generate udev rules: `openrgb --generate-udev-rules /etc/udev/rules.d/60-openrgb.rules`, then `udevadm control --reload-rules && udevadm trigger`.
- `uninstall()`: remove the binary, udev rules and `i2c.conf`.

### 80-lights (log §8.4–8.6)
- Install `bin/lights` to `/usr/local/bin/lights` and `config/systemd/lights-off.service`.
- Enable the boot service only if `LIGHTS_BOOT=off` in the config (the default). With `LIGHTS_BOOT=hardware`, leave it disabled so the motherboard's stored rainbow survives reboots (see log §8.6).
- `uninstall()`: disable and remove the service and the script.

---

## 6. Safety rules (must be enforced in code)

1. **Never disable password SSH login** unless `~/.ssh/authorized_keys` exists and contains a key. Validate the config with `sshd -t` **before** restarting, and roll back the drop-in if validation fails.
2. **Before `60-headless`**, require: Tailscale up (`tailscale status` succeeds), `ssh.socket` enabled, and sleep masked. If running locally (not over SSH), print a reminder to test `ssh <user>@<host>` from the client first.
3. **No automatic reboots.** Always ask.
4. **Secrets** (Wi-Fi password, Tailscale auth key) are never logged, echoed or written to the repo or config.
5. **Downloads:** HTTPS only; verify the SHA-256 for pinned binaries; abort on mismatch.

---

## 7. `beast doctor` checks

Each check prints ✅/❌ with a one-line fix hint. They're taken from the verification commands in the log:

| Check | Command | Pass when |
|---|---|---|
| OS | `/etc/os-release` | Ubuntu 24.04 or 26.04 |
| GPU | `nvidia-smi --query-gpu=name,driver_version,memory.used --format=csv,noheader` | succeeds |
| Boot target | `systemctl get-default` | `multi-user.target` |
| Sleep | `systemctl is-enabled sleep.target` | `masked` |
| SSH | `systemctl is-enabled ssh.socket` | `enabled` |
| SSH hardening | `sudo sshd -T` | `passwordauthentication no`, `permitrootlogin no` |
| Tailscale | `tailscale status` | succeeds |
| Wi-Fi (if used) | `nmcli -g connection.permissions,802-11-wireless-security.psk-flags,connection.autoconnect connection show "<name>"` | empty / `0` / `yes` |
| OpenRGB | `openrgb --noautoconnect -l` | lists the devices from the config |
| Lights boot service | `systemctl is-enabled lights-off.service` | matches `LIGHTS_BOOT` |
| Ghostty terminfo (informational) | `infocmp xterm-ghostty` | present, or a hint to run the client command |

---

## 8. `lights` design (replaces the hard-coded script in the log)

The script in the log works but hard-codes device indices `0–3`. The repo version must keep the **same behavior** while reading from the config.

**Commands:**
```
lights on            # LIGHTS_ON_* colors/modes from the config
lights off
lights <RRGGBB>      # everything one color
lights status        # print the detected devices and the configured mapping
lights detect        # run detection and write the device mapping to the config
```

**Config (`~/.config/beast/beast.conf`, with defaults matching this machine):**
```bash
OPENRGB_BIN=/usr/local/bin/openrgb
LIGHTS_BOOT=off                  # off | hardware

# Device mapping (resolved by name at runtime; indices are a fallback)
LIGHTS_RAM_DEVICES="ENE DRAM"    # all devices with this name: RAM sticks
LIGHTS_GPU_DEVICE="GeForce"
LIGHTS_MB_DEVICE="MSI MYSTIC LIGHT"
LIGHTS_MB_ZONES="0 1 2 3"        # JAF, JARGB 1, JARGB 2, JARGB 3
LIGHTS_MB_ZONE_SIZE=120

LIGHTS_ON_RAM_MODE=Rainbow
LIGHTS_ON_COLOR=FFFFFF           # GPU + motherboard color for `lights on`
```

**Hard requirements, learned from the setup log:**
1. Resolve device indices **by name** from `openrgb --noautoconnect -l` at runtime, since indices can change if hardware changes.
2. Run **one `openrgb` call per action** where possible; each call rescans the hardware and takes a few seconds.
3. For the MSI device: always use `-m Direct`, and **put `-z N -sz SIZE` before `-c COLOR` in the same call, for every zone.** Sizes don't carry over between calls.
4. RAM off: `-m Off`. GPU off: `-m Direct -c 000000`, then `-m Static -c 000000 -b 0` as a fallback (the GPU has no `Off` mode).
5. Always pass `--noautoconnect`.
6. Root is required for device access unless the udev rules are installed; with the rules, it works as a normal user.
7. `lights on` can't restore the motherboard's built-in rainbow (Direct only); `lights --help` should say so and point to the power-cycle method in `docs/troubleshooting.md`.

---

## 9. Testing

- **Lint:** `shellcheck` on all scripts (CI with GitHub Actions).
- **Unit tests:** `bats` tests for `lib/common.sh`, config parsing, and `lights` argument handling and command construction. Mock `openrgb` with a stub that prints the device list from `SETUP-LOG.md` §8.1 and records its arguments.
- **Container test:** run `install.sh --dry-run --yes` in an `ubuntu:24.04` container in CI. Hardware modules (`20-nvidia`, `70-openrgb`, `80-lights`) must detect the missing hardware and skip cleanly.
- **Real-machine acceptance:** on `beast`, `beast doctor` is all green, and running `beast install` a second time reports every module as "already done."

---

## 10. Phase 2 (planned; not part of the current setup)

These aren't in the setup log yet. Add them as separate, opt-in modules once implemented, and record them in `ROADMAP.md`:

### 90-tmux
- Config managed dotfiles-style: `dotfiles/tmux/tmux.conf` symlinked to `~/.config/tmux/tmux.conf`.
- Theme: **Rosé Pine** (`rose-pine/tmux`), installed via TPM.

### 91-neovim
- A recent Neovim release (Ubuntu's apt version may lag; use the official release binary, pinned with a checksum).
- Config in `dotfiles/nvim/`, symlinked to `~/.config/nvim`.
- Theme: **Rosé Pine** (`rose-pine/neovim`), with `lazy.nvim` as the plugin manager.

Symlinks must back up any existing files (`*.bak.<timestamp>`) before replacing them.

---

## 11. README outline

1. What this is (one paragraph, plus the hardware table from the log)
2. Quick install (the one-liner and the clone method)
3. Manual steps first (link to `docs/manual-steps.md`)
4. Modules table
5. `beast` and `lights` usage
6. Safety notes (SSH keys before hardening; headless confirmation)
7. Troubleshooting link
8. Roadmap link
