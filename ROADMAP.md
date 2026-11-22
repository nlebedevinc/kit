# Roadmap

## Done

Everything in [docs/SETUP-LOG.md](docs/SETUP-LOG.md): base packages, NVIDIA check, reliability (watchdog, panic reboot, smartd), Tailscale, SSH hardening, Wi-Fi, headless, OpenRGB, lights, and the `beast-check` health check.

## Before the first real run on beast

- [ ] Cross-check the OpenRGB 1.1 SHA-256 against the Codeberg release page
- [ ] `beast doctor`: 0 failures (the single-RAM-stick warning is expected until the kit is replaced)
- [ ] A second `beast install` reports every module `already`
- [ ] `beast install --non-interactive --json` by an agent over SSH finishes without hanging
- [ ] `beast-check` over `ssh -t` in Ghostty: check the ✔ / ! / ✘ alignment (a line break after each symbol was seen once); use `--ascii` until then

## Phase 2 (planned, not done on the machine yet)

Separate, opt-in modules. Symlinks back up existing files (`*.bak.<timestamp>`).

- **90-tmux**: `dotfiles/tmux/tmux.conf` → `~/.config/tmux/tmux.conf`; Rosé Pine (`rose-pine/tmux`) via TPM.
- **91-neovim**: a recent official release (pinned, checksummed); `dotfiles/nvim/` → `~/.config/nvim`; Rosé Pine (`rose-pine/neovim`) with `lazy.nvim`.
- **92-ups**: NUT (Network UPS Tools) for a USB UPS (planned: CyberPower CP1500PFCLCD, pure sine wave); shut down cleanly on low battery; a `ups` check in `beast-check`.
- **93-uptime-alert**: a cron ping to a healthchecks.io URL from the config (`HEALTHCHECK_URL`), so the owner gets an email when the server goes down.
- **Manual steps**: BIOS **Restore after AC Power Loss → Power On**; save an MSI **OC Profile** (slot and USB) for one-step recovery after a CMOS reset.
