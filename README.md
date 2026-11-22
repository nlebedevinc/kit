# kit

This is how I set up the machines I own. I keep the steps here as scripts, so I can rebuild a machine from a fresh OS install without trying to remember what I did last time, and run them again whenever something drifts.

Right now it covers one machine: **beast**, my home GPU server. It runs Ubuntu without a desktop, and I reach it from my laptop over SSH and Tailscale. Everything the scripts do comes from my notes in [the setup log](docs/SETUP-LOG.md).

| | beast |
|---|---|
| CPU | Intel Core Ultra 9 285K |
| GPU | RTX 5070 Ti, 16 GB |
| RAM | 2 × 32 GB DDR5 (one stick for now) |
| Board | MSI PRO Z890-P WIFI |
| OS | Ubuntu Desktop 24.04 / 26.04 |

## Setting up a fresh machine

First the parts I do by hand: BIOS settings, partitioning and installing Ubuntu ([manual steps](docs/manual-steps.md)). Then, on the new machine:

```sh
wget -qO- https://raw.githubusercontent.com/nlebedevinc/kit/main/install.sh | bash
```

(A fresh Ubuntu Desktop has `wget` but not `curl`. With `curl`: `curl -fsSL … | bash`.)

That downloads this repo to `~/.local/share/beast`, adds a `beast` command and runs the whole setup. To see what it would change first, add `-s -- --dry-run` after `bash`.

It stops when it needs me:

- a link to sign in to Tailscale
- `ssh-copy-id me@beast` from my laptop; SSH passwords stay on until my key is there
- a yes before it turns the desktop off for good
- the Wi-Fi password, if Ubuntu kept it in the desktop keyring

Then I run `beast install` again. Steps that are already done are skipped, so running it twice is safe. It never reboots on its own; it tells me when a reboot is needed.

## What it sets up

- system updates and the tools I use: git, tmux, htop, btop, nvtop, sensors
- a check that the NVIDIA driver works
- automatic recovery: a hardware watchdog, reboot after a kernel panic, disk health monitoring
- Tailscale, with key expiry turned off
- SSH with keys only, no root login
- Wi-Fi that connects at boot, before anyone logs in
- no sleep, and boot to the command line
- RGB control with OpenRGB, and the lights off at every boot
- a health check at the end

## Day to day

```sh
beast doctor       # is everything still healthy?
beast update       # pull the latest scripts, update the system, re-apply
beast plan         # what would change, without changing anything
beast gui start    # the desktop, until the next reboot
lights off         # or: on, 00AAFF
```

`beast --help` lists the rest. My settings live in `~/.config/beast/beast.conf`; the defaults in [config/beast.conf.example](config/beast.conf.example) match beast.

Secrets like the Wi-Fi password or a Tailscale auth key come from environment variables or a hidden prompt. They're never written to disk or logged.

## More

- [Troubleshooting](docs/troubleshooting.md)
- [Setting it up with an AI agent](docs/agent-install.md)
- [Notes for AI agents working on this repo](AGENTS.md)

Before the command was called `beast`, this repo installed a `kit` command. Its settings in `~/.config/kit/kit.conf` are picked up on the first run, and the old `--host beast` flag still works.

## License

[MIT](LICENSE)
