# Roadmap

## Done

- `kit` CLI, curl/wget bootstrap, host profiles
- `beast`: every step of the setup log (base packages, NVIDIA check, Tailscale, SSH hardening, Wi-Fi, headless, OpenRGB, lights)

## Before the first real run

- [x] Set the GitHub username in the install URLs and as the `KIT_REPO` default in `install.sh`
- [ ] Cross-check the OpenRGB 1.1 SHA-256 against the Codeberg release page
- [ ] Copyright holder in `LICENSE`
- [ ] On `beast`: `kit doctor` all green, and a second `kit install` reports every module "already done"

## Phase 2 (opt-in modules, not in the setup log yet)

- **tmux** (`modules/common/tmux.sh`): `dotfiles/tmux/tmux.conf` → `~/.config/tmux/tmux.conf`; Rosé Pine (`rose-pine/tmux`) via TPM.
- **neovim** (`modules/common/neovim.sh`): pinned official release with checksum; `dotfiles/nvim/` → `~/.config/nvim`; Rosé Pine (`rose-pine/neovim`), `lazy.nvim`.
- Symlinks back up existing files (`*.bak.<timestamp>`) first.

## Later

- **macbook** host (`hosts/macbook/`, `modules/macos/`): Homebrew packages, Ghostty config with `shell-integration-features = ssh-env,ssh-terminfo`, shared dotfiles. Needs its own setup log first.
- Short install URL (own domain redirecting to `install.sh`).
- `kit completion bash`.
