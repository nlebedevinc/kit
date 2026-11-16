# beast: troubleshooting

From [SETUP-LOG.md](SETUP-LOG.md) §9, plus what kit checks for. Start with `kit doctor`.

| Symptom | Cause | Fix |
|---|---|---|
| Machine boots Windows; no Ubuntu entry visible | MSI firmware shows one entry per drive | Put the **ubuntu** UEFI entry first in the firmware boot order |
| `ssh-copy-id`: "Could not resolve hostname" / "Permission denied" | It was run **on the server** against itself | Run `ssh-copy-id me@beast` **on the Mac** |
| `ssh-keygen` asks to overwrite | A key already exists | Answer **`n`** and reuse it |
| `systemctl is-enabled ssh` → `disabled` | SSH socket activation (Ubuntu 24.04+) | Expected. Check `ssh.socket` instead |
| `kit doctor`: SSH hardening fails although `99-hardening.conf` is installed | In `sshd_config.d` the **first** file that sets a value wins; another file (e.g. `50-cloud-init.conf`) sets it to `yes` | `kit doctor` names the file. Remove the setting from it, then `kit install ssh` |
| `sshd -t`: "Missing privilege separation directory: /run/sshd" | Socket activation creates it only on the first connection | `kit install ssh` creates it; by hand: `sudo install -d -m 0755 /run/sshd` |
| `nvtop`: cannot initialize terminal type `xterm-ghostty` | The server lacks Ghostty's terminfo | On the Mac: `infocmp -x xterm-ghostty \| ssh me@beast -- tic -x -`, or in Ghostty's config: `shell-integration-features = ssh-env,ssh-terminfo`. One-off: `TERM=xterm-256color nvtop` |
| `systemctl enable nvidia-persistenced`: "no installation config" | The unit is static (started via udev) | Nothing to do |
| `nvidia-smi` fails | Driver not installed or not loaded | `kit install nvidia --fix` (runs `ubuntu-drivers install`), then reboot |
| Wi-Fi doesn't connect without a desktop login | The password lives in the desktop keyring | `kit install wifi` (asks for the password once, stores it system-wide) |
| SSH drops after `kit install wifi` | NetworkManager restarted to apply the power-saving setting | Reconnect after ~15 s |
| `openrgb --list-devices` prints only "Connection attempt failed" | OpenRGB tries the SDK server first; no devices detected | Load the i2c modules (`kit install openrgb`); always use `--noautoconnect` |
| MSI controller not detected | Ubuntu's OpenRGB 0.9 snapshot predates this board | OpenRGB **1.1** AppImage (`kit install openrgb`) |
| AppImage: `libOpenGL.so.0` missing | Minimal Ubuntu | `sudo apt install libopengl0 libfuse2t64` (done by `kit install openrgb`) |
| `-m Off` / `-m Static` rejected for MSI | The controller supports only `Direct` | `kit lights` always uses `-m Direct` for it |
| MSI colors have no visible effect | Zones have 0 LEDs | Zone sizes must be set **in the same command** as the color: `kit lights` does `-z N -sz 120` before `-c` |
| `kit lights`: "no RGB devices found" | No udev rules (needs root) or i2c modules not loaded | `kit install openrgb`, or `sudo kit-lights …` |
| `kit lights`: "no device named …" | Hardware changed, or names differ | `kit lights detect`, then set `LIGHTS_*` in `~/.config/kit/kit.conf` and `kit install lights` |

## Getting the motherboard's own rainbow back

The MSI controller only takes static colors (`Direct`) from OpenRGB, so `kit lights on` can't restore the board's built-in rainbow animation. The stored effects come back after a **full power cycle**:

```bash
# ~/.config/kit/kit.conf
LIGHTS_BOOT=hardware
```

```bash
kit install lights        # disables the boot service that turns the lights off
sudo poweroff
# PSU switch off (or unplug) for about 30 s, then power on
```

## Getting the desktop back

```bash
kit gui start             # now (kit gui stop to end it)
kit gui on                # at every boot (kit gui off to undo)
kit uninstall headless    # also allows sleep again
```
