# Installing with an AI agent

Any agent that can run shell commands (locally, or over `ssh -t`) can install and check beast. It follows [AGENTS.md](../AGENTS.md).

## Before you start, in your own terminal

Secrets go in **your terminal on the server**, never in the agent's chat:

```bash
export TAILSCALE_AUTHKEY=…   # optional: unattended Tailscale login (otherwise you get a login link)
export TS_API_TOKEN=…        # optional: lets beast disable Tailscale key expiry
export WIFI_PSK=…            # only if the Wi-Fi password lived in the desktop keyring
sudo -v                      # so beast can use sudo without a terminal prompt
```

If the agent runs commands over SSH, it should use `ssh -t`, or you run `sudo -v` in that session first. Without either, beast stops with exit code 5 instead of hanging.

## The prompt

> Install the beast server setup on `beast` from `https://github.com/nlebedevinc/kit`. Read `AGENTS.md` first. Run `beast plan --json` and show me the plan before changing anything. Then install with `--non-interactive --json`, relay every manual action to me, never reboot, and finish with `beast doctor --json`, summarizing any warnings or failures.

Going headless needs `--yes` in non-interactive mode, and only happens once Tailscale is running and SSH works. Tell the agent explicitly if you want that step.
