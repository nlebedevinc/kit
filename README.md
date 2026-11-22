# beast

Scripts that turn a fresh Ubuntu Desktop into my headless GPU server, reached over SSH and Tailscale. Every step comes from [the setup log](docs/SETUP-LOG.md) of the real machine. Running it again is safe: anything already set up is left alone, and every install ends with a health check.

| Part | Model |
|---|---|
| CPU | Intel Core Ultra 9 285K |
| Motherboard | MSI PRO Z890-P WIFI |
| GPU | Gigabyte GeForce RTX 5070 Ti Eagle OC ICE, 16 GB |
| RAM | G.Skill Trident Z5 Neo RGB DDR5-6000, 2 × 32 GB (one stick for now) |
| Storage | 2 TB NVMe, shared with Windows |
| OS | Ubuntu Desktop 24.04 / 26.04 |

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash
```

This clones the repo to `~/.local/share/beast`, adds `beast` to `~/.local/bin` and runs `beast install`. To see what it would do first, add `-s -- --dry-run` after `bash`.

To read the code before running it:

```sh
git clone https://github.com/nlebedevinc/kit.git ~/.local/share/beast
~/.local/share/beast/install.sh
```

**Manual steps first:** BIOS settings, partitioning and the Ubuntu install itself aren't scripted. See [docs/manual-steps.md](docs/manual-steps.md).

**With an AI agent:** see [docs/agent-install.md](docs/agent-install.md) for a prompt that works with any agent that can run shell commands.

## Modules

| Module | Does |
|---|---|
| `00-preflight` | Checks the OS, session and sudo; creates `~/.config/beast/beast.conf` |
| `10-base-packages` | System upgrade; git, curl, tmux, htop, btop, nvtop, lm-sensors, smartmontools… |
| `20-nvidia` | Checks `nvidia-smi` (installs the driver only with `--fix`) |
| `25-reliability` | Hardware watchdog, reboot on kernel panic, SSD health monitoring |
| `30-tailscale` | Installs Tailscale, logs in, disables key expiry |
| `40-ssh` | Key-only SSH, no root login |
| `50-wifi` | Wi-Fi that connects at boot without a login, whatever the device is called |
| `60-headless` | No sleep; boots to the command line |
| `70-openrgb` | OpenRGB 1.1 (pinned, checksummed) for the RAM, GPU and motherboard lights |
| `80-lights` | The `lights` command; lights off at every boot |
| `99-verify` | Installs and runs `beast-check` |

## Usage

```sh
beast install              # everything, then the health check
beast install tailscale    # one module (plus preflight and the health check)
beast plan                 # what install would do; changes nothing
beast list                 # what's applied
beast doctor               # the health check
beast update               # git pull, system upgrade, then install
beast uninstall lights     # undo reliability, headless, openrgb or lights
beast config               # the settings in effect (secrets hidden)
beast gui start            # the desktop, until the next boot (gui on: for good)
```

Add `--json` for machine-readable output, `--non-interactive` to never prompt, and `--yes` to accept confirmations. `beast describe` lists everything, including exit codes.

`beast-check` also works on its own (it's installed to `/usr/local/bin`): `beast-check --strict`, `--section network`, `--json`, `--ascii`.

```sh
lights off                 # also: on, 00AAFF, status, detect
```

Settings live in `~/.config/beast/beast.conf`; the defaults match this machine. See [config/beast.conf.example](config/beast.conf.example).

## Coming from kit

This repo used to install a `kit` command. Everything its install did still works; the command is now `beast`:

- The old one-liner's `--host beast` is still accepted.
- Settings in `~/.config/kit/kit.conf` are copied into `~/.config/beast/beast.conf` on the first run.
- `kit-lights` and `kit-lights-off.service` are replaced by `lights` and `lights-off.service` (after asking).
- `kit update`, `kit config` and `kit uninstall headless` are `beast update`, `beast config` and `beast uninstall headless`.

## Safety

- SSH password login is turned off only once your key is on the server, and the new config is checked with `sshd -t` before SSH restarts.
- Going headless needs Tailscale running, SSH enabled and an explicit yes.
- beast never reboots. It tells you when a reboot is needed.
- Secrets (Wi-Fi password, Tailscale keys) come from environment variables or a hidden prompt. They're never written to disk, logged or put on a command line.

## More

- [Troubleshooting](docs/troubleshooting.md)
- [Roadmap](ROADMAP.md)
- [For AI agents](AGENTS.md)

## License

[MIT](LICENSE)
