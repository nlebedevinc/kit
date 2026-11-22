# beast: setup log

This is a record of how this home GPU server was set up, from a fresh Ubuntu install through to a headless, SSH-only machine with scripted RGB control. It covers **only the steps we actually performed**. Items whose completion wasn't confirmed are listed separately in [Section 13](#13-to-verify-outcome-not-confirmed). Sections 10–12 cover a RAM failure in November 2026 and the reliability changes made afterwards.

---

## Machine

| Part | Model |
|---|---|
| System | PowerSpec G495 (Micro Center) |
| CPU | Intel Core Ultra 9 285K (24 cores, 8P + 16E) |
| Motherboard | MSI PRO Z890-P WIFI (4× M.2, 4× DDR5 slots) |
| GPU | Gigabyte GeForce RTX 5070 Ti Eagle OC ICE, 16 GB GDDR7 |
| RAM | 64 GB G.Skill Trident Z5 Neo RGB DDR5-6000 kit (2 × 32 GB). **Currently 1 stick (32 GB) in DIMMA2**: the other stick failed (Section 10) |
| Storage | 1× 2 TB NVMe SSD (shared by Windows and Ubuntu) |
| PSU / cooling | 1200 W 80+ Gold, 360 mm AIO liquid cooler |
| Network | Wi-Fi 7 (Intel BE200), 5 GbE (currently on Wi-Fi) |
| Hostname / user | `beast` / `me` |
| Client | MacBook (Ghostty terminal), connected over Tailscale |

---

## 1. Firmware (MSI BIOS)

MSI keys: **Delete** = BIOS, **F7** = Advanced Mode, **F10** = save and exit, **F11** = one-time boot menu.

- **Memory:** originally **XMP → Profile 1** (DDR5-6000). After the RAM failure in Section 10, changed to **Standard** (XMP off; runs at 5600 MT/s, within Intel's spec for the 285K with regular UDIMMs).
- **Boot order:** the Ubuntu UEFI entry was set **first**, so the machine always boots Ubuntu (see Section 2.4). It had to be set again after the CMOS reset in Section 10.

---

## 2. Dual boot on a single 2 TB drive

### 2.1 Starting layout (factory Windows)

| Partition | Type | Size | Role |
|---|---|---|---|
| `nvme0n1p1` | vfat | 104.86 MB | EFI System Partition (labeled "Windows Boot Manager") |
| `nvme0n1p2` | — | 16.78 MB | Microsoft Reserved |
| `nvme0n1p3` | NTFS | 2.00 TB | Windows `C:` |
| `nvme0n1p4` | NTFS | 524 MB | Windows Recovery |

### 2.2 Making room

`nvme0n1p3` (Windows) was shrunk to free space for Ubuntu.

### 2.3 Ubuntu installation (manual partitioning)

- **Edition:** regular **Ubuntu Desktop** (rather than Server), so a GUI stays available as a fallback. The desktop is disabled at boot afterwards (Section 6).
- **Partitions:**
  - The free space became **one ext4 partition mounted at `/`**.
  - `nvme0n1p1` was **reused as the EFI System Partition** (`/boot/efi`) and **not formatted**. It's shared with Windows, so Ubuntu adds `EFI/ubuntu` next to `EFI/Microsoft`.
  - Boot loader location: **`nvme0n1`**.
  - `nvme0n1p2`, `nvme0n1p3` and `nvme0n1p4` were left untouched.
  - No swap partition (Ubuntu creates a swap file).
- **Account:** user `me`, hostname `beast`, password required at login.

### 2.4 First boot

After installation, the machine booted straight into Windows, and the firmware showed only "Windows Boot Manager." This is common with MSI boards when both systems share one drive. The fix was putting the **ubuntu** entry first in the firmware boot order.

Windows remains available from the one-time boot menu: **F11 → Windows Boot Manager**.

---

## 3. Base system

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y openssh-server build-essential git curl tmux htop btop nvtop lm-sensors
sudo reboot
```

The installed release is **Ubuntu 26.04.1 LTS** (kernel `7.0.0-43-generic`), confirmed by the SSH login banner and `beast-check`.

---

## 4. NVIDIA driver

The NVIDIA driver was already installed after the Ubuntu install. Verified with:

```bash
nvidia-smi
```

Result:
- **Driver 595.99.02**, supporting CUDA up to **13.2**
- RTX 5070 Ti detected; headless idle at **34 MiB / 16303 MiB** used, about **13 W**, **35 °C**, fans at 0%

`nvidia-persistenced` runs automatically on Ubuntu (it's a *static* unit, so `systemctl enable` reports "no installation config"). Persistence mode reports **Disabled**; it was left as is.

---

## 5. Remote access

### 5.1 Tailscale (server)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up            # sign in through the printed link
```

The Tailscale app on the Mac is signed into the same account. MagicDNS makes the server reachable as `beast`.

### 5.2 SSH key login (from the Mac)

The Mac already had an ed25519 key. **When `ssh-keygen` offered to overwrite it, the answer was `n`.** The existing key was copied to the server:

```bash
# On the Mac
ssh-copy-id me@beast
ssh me@beast                 # logs in without a password
```

### 5.3 SSH hardening (server)

Settings go in a drop-in file, which takes priority over the main `sshd_config`:

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo systemctl restart ssh
sudo sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin'
```

On Ubuntu 24.04+, SSH uses socket activation: `systemctl is-enabled ssh` reports `disabled` while **`ssh.socket`** is the enabled unit. That's expected.

---

## 6. Headless mode

### 6.1 Wi-Fi that connects without a login

A Wi-Fi network saved from the desktop can store its password in the **user session**. With no desktop login, it would never connect. The profile was made system-wide:

```bash
nmcli -f NAME,TYPE,DEVICE connection show --active

sudo nmcli connection modify "WIFI-NAME" connection.permissions "" \
  802-11-wireless-security.psk-flags 0 connection.autoconnect yes
sudo nmcli connection modify "WIFI-NAME" wifi-sec.psk 'WIFI-PASSWORD'
```

Wi-Fi power saving turned off, for stable SSH:

```bash
printf '[connection]\nwifi.powersave = 2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```

### 6.2 Never sleep

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### 6.3 Boot to the command line (desktop off)

```bash
sudo systemctl set-default multi-user.target
sudo reboot
```

Confirmed afterwards: no desktop on the local screen; `ssh me@beast` works from the Mac; the monitor can be unplugged.

**Desktop available as a fallback:**

```bash
sudo systemctl start gdm                       # temporary (stop: sudo systemctl stop gdm)
sudo systemctl set-default graphical.target    # permanent
```

---

## 7. Client: Ghostty terminal type

Running `nvtop` over SSH failed with:

```
ncurses: cannot initialize terminal type ($TERM="xterm-ghostty")
```

Fixes:

```bash
# One-off, on the server
TERM=xterm-256color nvtop

# Permanent: run on the Mac to install Ghostty's terminfo on the server
infocmp -x xterm-ghostty | ssh me@beast -- tic -x -
```

Ghostty can also do this automatically for every host, via its config on the Mac:

```
shell-integration-features = ssh-env,ssh-terminfo
```

---

## 8. RGB lighting control (OpenRGB)

### 8.1 What's controllable

| OpenRGB device | Hardware | Modes that work |
|---|---|---|
| `0`, `1`: ENE DRAM | The two RAM sticks (SMBus `/dev/i2c-1`, addresses `0x71`, `0x73`) | `Off`, `Static`, `Rainbow` and others |
| `2`: Gigabyte GeForce RTX 5070 Ti Eagle OC ICE | GPU side LED strip (SMBus `/dev/i2c-2`, `0x75`) | `Static`, `Direct` (no `Off`) |
| `3`: MSI MYSTIC LIGHT | Motherboard ARGB controller (USB `0db0:0076`, 761-byte protocol): fans, cooler, case | **`Direct` only.** Zones: `JAF`, `JARGB 1`, `JARGB 2`, `JARGB 3` |

### 8.2 SMBus access (RAM and GPU)

```bash
sudo modprobe -a i2c-dev i2c-i801        # -a is required: two module names without it load only the first
printf 'i2c-dev\ni2c-i801\n' | sudo tee /etc/modules-load.d/i2c.conf
```

### 8.3 OpenRGB version

Ubuntu's `openrgb` package (`0.9+git20251009`) detected the RAM and GPU, but **not** the MSI controller. **OpenRGB 1.1** (AppImage) detects all four devices.

```bash
mkdir -p ~/apps/openrgb && cd ~/apps/openrgb
wget https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_1.1/OpenRGB_1.1_x86_64_8e16de2.AppImage
chmod +x OpenRGB_1.1_x86_64_8e16de2.AppImage
sudo apt install -y libfuse2t64 libopengl0    # needed by the AppImage on Ubuntu

sudo apt remove -y openrgb
sudo install -m 755 OpenRGB_1.1_x86_64_8e16de2.AppImage /usr/local/bin/openrgb
sudo openrgb --generate-udev-rules /etc/udev/rules.d/60-openrgb.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Useful flags in 1.1: `-l` (short list), `-ld` (detailed list), `--noautoconnect` (skips the harmless "Connection attempt failed" message), `-z` (zone), `-sz` (zone size).

### 8.4 The key finding: MSI zone sizes

The MSI ARGB zones start with **0 LEDs** configured, so colors had no effect. **Zone sizes must be set in the same command as the color.** Sizes set in a separate command don't carry over. This command worked:

```bash
sudo openrgb --noautoconnect -d 3 -m Direct \
  -z 0 -sz 120 -c FF0000 \
  -z 1 -sz 120 -c FF0000 \
  -z 2 -sz 120 -c FF0000 \
  -z 3 -sz 120 -c FF0000
```

### 8.5 The `lights` command

`/usr/local/bin/lights`:

```bash
#!/usr/bin/env bash
# Usage: lights on | lights off | lights COLOR (hex, e.g. lights 00AAFF)
O="/usr/local/bin/openrgb --noautoconnect"

# MSI fans/cooler/case: zone sizes must be set in the same command as the color
msi() {
  echo -d 3 -m Direct \
    -z 0 -sz 120 -c "$1" -z 1 -sz 120 -c "$1" \
    -z 2 -sz 120 -c "$1" -z 3 -sz 120 -c "$1"
}

case "$1" in
  off)
    $O -d 0 -m Off -d 1 -m Off -d 2 -m Direct -c 000000 $(msi 000000)
    $O -d 2 -m Static -c 000000 -b 0 > /dev/null
    echo "Lights off" ;;
  on)
    $O -d 0 -m Rainbow -d 1 -m Rainbow -d 2 -m Static -c FFFFFF -b 100 $(msi FFFFFF)
    echo "Lights on" ;;
  [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
    $O -d 0 -m Static -c "$1" -d 1 -m Static -c "$1" -d 2 -m Static -c "$1" -b 100 $(msi "$1")
    echo "Lights set to #$1" ;;
  *)
    echo "Usage: lights on | lights off | lights RRGGBB"; exit 1 ;;
esac
```

`/etc/systemd/system/lights-off.service`:

```ini
[Unit]
Description=Turn off RGB lights at boot
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lights off

[Install]
WantedBy=multi-user.target
```

```bash
sudo chmod +x /usr/local/bin/lights
sudo systemctl daemon-reload
sudo systemctl enable lights-off.service
```

### 8.6 Limitation: the original rainbow

The MSI controller only accepts `Direct` (static colors) from OpenRGB, so `lights on` can't bring back the motherboard's built-in rainbow animation. The hardware-stored effects return after a **full power cycle**:

```bash
sudo systemctl disable lights-off.service    # otherwise lights go off again at boot
sudo poweroff
# PSU switch off (or unplug) for about 30 s, then power on
```

---

## 9. Problems we hit, and their fixes

| Symptom | Cause | Fix |
|---|---|---|
| Machine boots Windows; no Ubuntu entry visible | MSI firmware shows one entry per drive | Put the **ubuntu** UEFI entry first in the firmware boot order |
| `ssh-copy-id`: "Could not resolve hostname" / "Permission denied" | It was run **on the server** against itself; the hostname was a placeholder | Run `ssh-copy-id me@beast` **on the Mac** |
| `ssh-keygen` asks to overwrite | A key already exists | Answer **`n`** and reuse it |
| `systemctl is-enabled ssh` → `disabled` | SSH socket activation | Check `ssh.socket` instead |
| `nvtop`: cannot initialize `xterm-ghostty` | Server lacks Ghostty's terminfo | `infocmp -x xterm-ghostty \| ssh me@beast -- tic -x -` |
| `systemctl enable nvidia-persistenced`: "no installation config" | The unit is static (started via udev) | Nothing to do |
| `openrgb --list-devices` prints only "Connection attempt failed" | OpenRGB tries the SDK server first; no devices were detected | Load the i2c modules; use `--noautoconnect` |
| MSI controller not detected | OpenRGB 0.9 snapshot predates this board | OpenRGB **1.1** AppImage |
| AppImage: `libOpenGL.so.0` missing | Minimal Ubuntu | `sudo apt install libopengl0` (plus `libfuse2t64`) |
| `-m Off` / `-m Static` rejected for MSI | Controller supports only `Direct` | Use `-m Direct` |
| MSI colors have no visible effect | Zones have 0 LEDs | Set `-z N -sz 120` **in the same command** as `-c` |

---

## 10. Incident: RAM stick failure (Nov 19–22, 2026)

### 10.1 What happened

After about three days of uptime, `beast` stopped answering SSH and Tailscale while still powered on. After a power-off it no longer booted:

- At power-on it started, reset once, then kept running with fans and RGB on (RGB at the hardware default, so `lights-off.service` never ran).
- No video on any port; the keyboard didn't respond.
- The **DRAM EZ Debug LED** (yellow) flashed briefly during startup.

### 10.2 Diagnosis, in order

| Step | Result |
|---|---|
| Power drain (PSU off, unplugged) several times; GPU reseated | No change |
| Clear CMOS: cord unplugged, coin battery out, power button held 30 s, 30 min wait | No change on its own |
| One stick moved to slot 1 (DIMMA1) | CPU (red) and DRAM (yellow) LEDs alternated continuously: memory training failing |
| **Stick X alone in DIMMA2** | **Booted** |
| BIOS memory set to **Standard** (XMP off) | Saved |
| Both sticks in DIMMA2 + DIMMB2, Standard | Failed to boot |
| **Stick Y alone in DIMMA2**, Standard | **Failed to boot**: stick Y is faulty |

The previous boot's journal (`journalctl -b -3`) ends normally at **08:30:18 on Nov 19** with routine jobs; the next 10-minute `sysstat` sample never ran. `sar` for that morning showed the CPU **99.99% idle** and about **0.8% of RAM** in use. No machine-check or hardware errors were logged. Conclusion: a sudden hardware freeze at idle, consistent with stick Y failing.

### 10.3 Side effects of the CMOS reset, and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Boot order back to Windows first | CMOS reset | **ubuntu** first again in BIOS |
| Clock reset to Sep 16, 2026 (boot list out of order) | CMOS reset | Fixed itself once online: NTP synchronized, RTC updated (`timedatectl`) |
| Tailscale unreachable; `nmcli connection up`: "no suitable device found" | The Wi-Fi device was renamed `wlp129s0f0` → **`wlp130s0f0`** (Ethernet `82:00.0` → `83:00.0`), and the saved profile was tied to the old name | Reconnected with `nmcli device wifi connect`; see 11.1 |

---

## 11. Reliability changes (after the incident)

### 11.1 Wi-Fi profile: cleaned up and not tied to a device name

Reconnecting had created duplicates (`WIFI-NAME`, `WIFI-NAME 1` … `WIFI-NAME 4`). The four inactive ones were deleted by UUID, and the active one was renamed and made robust:

```bash
nmcli connection show
sudo nmcli connection delete <UUID-1> <UUID-2> <UUID-3> <UUID-4>
sudo nmcli connection modify <ACTIVE-UUID> \
  connection.id "WIFI-NAME" \
  connection.interface-name "" \
  connection.permissions "" \
  802-11-wireless-security.psk-flags 0 \
  connection.autoconnect yes
```

`connection.interface-name ""` means the profile works whatever the Wi-Fi device is called after a hardware or firmware change. The `netplan-enp130s0` Ethernet profile was left as is.

### 11.2 Auto-recovery: hardware watchdog and reboot on kernel panic

```bash
sudo mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nRuntimeWatchdogSec=30s\nRebootWatchdogSec=2min\n' | sudo tee /etc/systemd/system.conf.d/watchdog.conf
printf 'kernel.panic = 10\n' | sudo tee /etc/sysctl.d/99-panic-reboot.conf
sudo systemctl daemon-reexec
sudo sysctl --system
```

If the system hangs, the hardware watchdog reboots it within about 30 s; after a kernel panic it reboots after 10 s. No reboot was needed to apply this.

### 11.3 SSD health monitoring

```bash
sudo apt install -y smartmontools      # also enables smartd, which monitors the drive continuously
sudo smartctl -H /dev/nvme0            # PASSED, 0 media errors, 0% used
```

### 11.4 Tailscale key expiry disabled

Key expiry for `beast` (it would have expired on 2027-05-14) was disabled in the Tailscale admin console. There is no `tailscale` CLI command for this on the machine itself; the alternative is the API (`POST /api/v2/device/<nodeId>/key` with `{"keyExpiryDisabled": true}`).

### 11.5 `beast-check` health report

A script that checks the whole setup and prints ✔ / ! / ✘ per line, installed from the Mac:

```bash
scp ~/Downloads/beast-check me@beast:
ssh -t me@beast 'sudo apt install -y smartmontools && sudo install -m 755 ~/beast-check /usr/local/bin/beast-check'
ssh -t me@beast beast-check
```

`ssh -t` is required: without a terminal, `sudo` fails with "A terminal is required to authenticate."

Result on Nov 22, 2026: **24 passed, 2 warnings, 0 failed** (warnings: one RAM stick; Tailscale key expiry, since fixed). Confirmed by it: Standard memory at 5600 MT/s, GPU 32 °C, CPU 33 °C, NVMe healthy, 8 GB swap, watchdog 30 s, panic reboot 10 s, clean previous shutdown, Wi-Fi profile not tied to a device name, NTP synced, SSH keys-only, headless target, sleep masked, `lights-off.service` enabled.

---

## 12. Problems from the incident

| Symptom | Cause | Fix |
|---|---|---|
| No video, keyboard dead, DRAM LED flashes | Failed RAM stick (stick Y) | Run on the good stick in DIMMA2; replace the kit |
| Red/yellow LEDs alternating | Memory training failing (stick in DIMMA1 / bad stick) | One stick, DIMMA2, wait up to 10 min after any memory change |
| "Clear CMOS didn't work" | First boot after a reset retrains 64 GB DDR5 and can stay black for minutes | Wait up to 10 minutes before cutting power |
| `journalctl` prompt: "terminal is not fully functional" | Ghostty terminfo missing on the server | `--no-pager`, or install the terminfo (Section 7) |
| `scp: stat local "beast-check": No such file` | Mac terminal not in Downloads | `scp ~/Downloads/beast-check me@beast:` |
| `sudo: A terminal is required to authenticate` | `ssh host 'sudo …'` without a TTY | `ssh -t` |

---

## 13. To verify (outcome not confirmed)

- [ ] Windows partition size after shrinking: `lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT`
- [ ] Ghostty terminfo installed on the server: `infocmp xterm-ghostty`
- [ ] Ghostty `shell-integration-features` set on the Mac
- [ ] `beast-check` after the key-expiry change shows the Tailscale line as ✔
