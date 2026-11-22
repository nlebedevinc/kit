# Troubleshooting

Start with `beast doctor`: every warning and failure comes with a fix. Section numbers refer to [SETUP-LOG.md](SETUP-LOG.md).

## Setup (§9)

| Symptom | Cause | Fix |
|---|---|---|
| Machine boots Windows; no Ubuntu entry | MSI firmware shows one entry per drive | Put **ubuntu** first in the boot order |
| `ssh-copy-id`: "Could not resolve hostname" / "Permission denied" | Run on the server against itself | Run `ssh-copy-id me@beast` **on the Mac** |
| `ssh-keygen` asks to overwrite | A key already exists | Answer **n** and reuse it |
| `systemctl is-enabled ssh` → `disabled` | SSH socket activation | Check `ssh.socket` instead (expected) |
| `nvtop`: cannot initialize `xterm-ghostty` | Server lacks Ghostty's terminfo | `infocmp -x xterm-ghostty \| ssh me@beast -- tic -x -` |
| `systemctl enable nvidia-persistenced`: "no installation config" | The unit is static (started by udev) | Nothing to do |
| `openrgb --list-devices` prints only "Connection attempt failed" | OpenRGB tries its SDK server first; no devices found | Load the i2c modules; use `--noautoconnect` (`beast install openrgb`) |
| MSI controller not detected | Ubuntu's OpenRGB 0.9 snapshot is too old | OpenRGB **1.1** AppImage (`beast install openrgb`) |
| AppImage: `libOpenGL.so.0` missing | Minimal Ubuntu | `sudo apt install libopengl0 libfuse2t64` |
| `-m Off` / `-m Static` rejected for MSI | The controller only supports `Direct` | Use `-m Direct` (`lights` does) |
| MSI colors have no visible effect | Zones have 0 LEDs | `-z N -sz 120` **in the same command** as `-c` (`lights` does) |

## The incident (§12)

| Symptom | Cause | Fix |
|---|---|---|
| No video, keyboard dead, DRAM LED flashes | Failed RAM stick | Run on the good stick in DIMMA2; replace the kit |
| Red/yellow LEDs alternating | Memory training failing (DIMMA1 or a bad stick) | One stick, DIMMA2, wait up to 10 minutes after any memory change |
| "Clear CMOS didn't work" | The first boot after a reset retrains DDR5 and can stay black for minutes | Wait up to 10 minutes before cutting power |
| `journalctl`: "terminal is not fully functional" | Ghostty terminfo missing on the server | `--no-pager`, or install the terminfo |
| `nmcli connection up`: "no suitable device found" | The Wi-Fi device was renamed; the profile was tied to the old name | `beast install wifi` (sets `connection.interface-name ""`) |
| `sudo: A terminal is required to authenticate` | `ssh host 'sudo …'` without a TTY | `ssh -t`, or `sudo -v` first (beast exits 5 in this case) |

## Getting the motherboard's rainbow back (§8.6)

The MSI controller only takes static colors from OpenRGB, so `lights on` can't restore its built-in rainbow. The stored effects come back after a full power cycle:

```bash
# in ~/.config/beast/beast.conf: LIGHTS_BOOT=hardware
beast install lights          # disables lights-off.service
sudo poweroff
# PSU switch off (or unplug) for about 30 s, then power on
```

## Getting the desktop back

```bash
beast gui start    # now, until the next boot (stop: beast gui stop)
beast gui on       # boot to the desktop from now on
```
