# kit

[![ci](https://github.com/nlebedevinc/kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nlebedevinc/kit/actions/workflows/ci.yml)

Scripts that take my machines from a fresh OS install to a working setup with one command. It's safe to run again: anything already set up is left alone.

## Install

On a fresh Ubuntu Desktop:

```sh
wget -qO- https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
```

If curl is installed, this works too:

```sh
curl -fsSL https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash -s -- --host beast
```

The installer clones this repo to `~/.local/share/kit`, adds a `kit` command to `~/.local/bin` and runs the setup. Add `--dry-run` to see what it would change without changing anything.

If you'd rather read the code first:

```sh
git clone https://github.com/nlebedevinc/kit.git ~/.local/share/kit
~/.local/share/kit/install.sh --host beast --dry-run
```

A few things have to be done by hand first: BIOS settings, partitioning and the Ubuntu install itself. See [manual steps](docs/hosts/beast/manual-steps.md).

## Hosts

| Host | OS | What it is |
|---|---|---|
| `beast` | Ubuntu Desktop 24.04 / 26.04 | Headless GPU server, reached over SSH and Tailscale |

Each host lives in `hosts/<name>/`. Its `host.conf` lists the modules to run and their settings.

## What it sets up on `beast`

| Module | |
|---|---|
| `preflight` | Checks the OS and creates `~/.config/kit/kit.conf` |
| `base-packages` | System upgrade, plus git, curl, tmux, htop, btop, nvtop and friends |
| `nvidia` | Checks that the NVIDIA driver works |
| `tailscale` | Installs Tailscale and logs in |
| `ssh` | Key-only SSH login, no root login |
| `wifi` | Wi-Fi that connects at boot without a desktop login |
| `headless` | No sleep, boots to the command line |
| `openrgb` | OpenRGB 1.1 for the RAM, GPU and motherboard lights |
| `lights` | The `kit lights` command and a boot service that turns the lights off |

The full record of how the machine was set up by hand is in [SETUP-LOG.md](docs/hosts/beast/SETUP-LOG.md).

## Usage

```sh
kit install              # run every module
kit install ssh wifi     # run only these
kit list                 # what's applied
kit doctor               # check everything, with a fix for each problem
kit update               # pull the latest kit and re-run
kit uninstall lights     # undo a module (openrgb, lights, headless)
kit config               # show current settings

kit gui start            # bring the desktop back for now
kit gui on               # boot to the desktop again

kit lights off           # also: on, 00AAFF, status, detect
```

Flags: `--host NAME`, `--dry-run`, `--yes`, `--verbose`, `--fix`.

## Configuration

Defaults live in `hosts/<name>/host.conf`. Override anything in `~/.config/kit/kit.conf`, for example:

```sh
LIGHTS_BOOT=hardware      # keep the motherboard's own lighting at boot
WIFI_CONNECTION="Home"    # instead of auto-detecting it
```

## Safety

kit won't lock you out of a machine you can only reach over the network:

- SSH password login is turned off only after your key is on the server.
- The machine goes headless only once Tailscale and SSH are working.
- It never reboots or restarts the network without asking.
- `--yes` skips confirmations, but never these checks.

Secrets aren't stored. The Wi-Fi password is asked for at a hidden prompt, and the Tailscale auth key is read from `TAILSCALE_AUTHKEY`. Neither is written to the repo or the config, or shown in output.

## Adding a host

1. Write down what you did by hand, like [SETUP-LOG.md](docs/hosts/beast/SETUP-LOG.md).
2. Create `hosts/<name>/host.conf` with `KIT_OS`, `KIT_MODULES` and any settings.
3. Reuse modules from `modules/<os>/`. Put anything specific to that machine in `hosts/<name>/modules/`.

## Development

```sh
shellcheck bin/kit install.sh lib/*.sh modules/*/*.sh
bats tests/
```

The core has to run on macOS's built-in bash 3.2, so it can set up a Mac later.

Having trouble? See [troubleshooting](docs/hosts/beast/troubleshooting.md).

## License

[MIT](LICENSE)
