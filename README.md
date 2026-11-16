# kit

Set up my machines from a fresh OS install with one command. Each machine has a **host profile** under [`hosts/`](hosts); kit applies it step by step, safely, and can run again at any time.

| Host | OS | What it is |
|---|---|---|
| `beast` | Ubuntu Desktop 24.04 / 26.04 | Headless home GPU server, SSH over Tailscale, scripted RGB |

`beast` hardware: PowerSpec G495 · Intel Core Ultra 9 285K · MSI PRO Z890-P WIFI · RTX 5070 Ti 16 GB · 64 GB DDR5-6000 · 2 TB NVMe (shared with Windows) · Wi-Fi 7.

## Quick install

On a fresh Ubuntu Desktop, logged in, connected to the network:

```bash
wget -qO- https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
# or, once curl is installed:
curl -fsSL https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
```

The one command is the whole install: it adds git and curl if missing, downloads kit to `~/.local/share/kit`, links `~/.local/bin/kit` and runs `kit install`. Running it again updates kit and re-applies (nothing changes if nothing needs to).

Prefer to read first:

```bash
git clone https://github.com/nlebedevinc/kit.git ~/.local/share/kit
~/.local/share/kit/install.sh --host beast --dry-run    # see what it would do
~/.local/share/kit/install.sh --host beast
```

Options: `KIT_REPO`, `KIT_REF` (branch), `KIT_PATH` (clone folder), e.g. `… | KIT_REF=dev bash -s -- --dry-run`.

## Before you start

BIOS, partitioning and the Ubuntu installer are manual: [docs/hosts/beast/manual-steps.md](docs/hosts/beast/manual-steps.md).

## Modules (beast)

Run in this order. Each one is skipped if it doesn't apply, reported "already done" if it's applied, and applied otherwise.

| Module | What it does | Setup log |
|---|---|---|
| `preflight` | Checks the OS, creates `~/.config/kit/kit.conf` | — |
| `base-packages` | Full upgrade, then `openssh-server build-essential git curl tmux htop btop nvtop lm-sensors` | §3 |
| `nvidia` | Checks the driver with `nvidia-smi` (installs it only with `--fix`) | §4 |
| `tailscale` | Installs Tailscale, `tailscale up` | §5.1 |
| `ssh` | Key-only login, no root login (only once your key is on the server) | §5.2–5.3 |
| `wifi` | Wi-Fi that connects at boot without a login; power saving off | §6.1 |
| `headless` | Never sleep; boot to the command line (only once Tailscale and SSH work) | §6.2–6.3 |
| `openrgb` | i2c modules, pinned OpenRGB 1.1 AppImage (SHA-256 checked), udev rules | §8.2–8.3 |
| `lights` | `kit lights` / `kit-lights`, boot service per `LIGHTS_BOOT` | §8.4–8.6 |

## Usage

```
kit install [module...]   run all modules, or the ones named
kit list                  ✅ applied · ⬜ not applied · ⏭ not applicable
kit doctor                every check, with a fix hint for each failure
kit update                pull kit, update packages, re-run install
kit uninstall <module>    revert (openrgb, lights, headless)
kit hosts | config        host profiles · effective settings (secrets hidden)
kit gui on|off|start|stop desktop at boot on/off, or start/stop it now

kit lights on | off | RRGGBB | status | detect

Flags: --host NAME  --dry-run  --yes  --verbose  --fix  --no-color
```

Settings: `hosts/beast/host.conf` holds the defaults; put your changes in `~/.config/kit/kit.conf` (see `kit config`).

## Safety

- **SSH password login is only turned off once `~/.ssh/authorized_keys` has a key**, and, when you run kit at the machine itself, after you confirm a key login from your client works. The config is checked with `sshd -t` first and rolled back if sshd rejects it.
- **Headless only after Tailscale is connected and SSH is enabled**, and after you confirm. Never reboots without asking.
- **Secrets stay secret:** the Wi-Fi password is typed at a hidden prompt and passed to NetworkManager on stdin (never on a command line); `TAILSCALE_AUTHKEY` comes from the environment and is hidden in all output. Neither is written to the repo or the config.
- `--yes` answers ordinary confirmations; it never skips a safety check.
- `--dry-run` shows every command without running it.

## Adding a host

1. Write down what you did, like [docs/hosts/beast/SETUP-LOG.md](docs/hosts/beast/SETUP-LOG.md).
2. Create `hosts/<name>/host.conf` with `KIT_OS` and `KIT_MODULES` (plus settings).
3. Reuse `modules/<os>/` and `modules/common/`; put host-only modules in `hosts/<name>/modules/` and host commands in `hosts/<name>/commands/`.

## More

- [Troubleshooting](docs/hosts/beast/troubleshooting.md)
- [Roadmap](ROADMAP.md)
- [Requirements](SPEC.md)
- Development: `shellcheck` + `bats tests/` (the core must run on macOS's bash 3.2)
