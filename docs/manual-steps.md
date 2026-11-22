# Manual steps

beast starts from a running Ubuntu Desktop. These steps come before it, or happen on the client. Section numbers refer to [SETUP-LOG.md](SETUP-LOG.md).

## 1. BIOS (MSI)

Keys: **Delete** = BIOS, **F7** = Advanced Mode, **F10** = save and exit, **F11** = one-time boot menu.

- **Memory: Standard**, not XMP. The freeze and the failed stick in §10 happened with XMP at 6000 MT/s. Standard runs at 5600 MT/s, Intel's spec for the 285K with regular UDIMMs. `beast doctor` warns (`ram.speed`) if the speed goes above `RAM_MAX_MTS`.
- **Boot order: `ubuntu` first.** Otherwise the board boots Windows, which shows up as the only entry (§2.4). Windows stays available with **F11 → Windows Boot Manager**.

## 2. After any CMOS reset

- Set the boot order (`ubuntu` first) and memory (Standard) again.
- The clock may jump back to an old date; it fixes itself once the machine is online and NTP syncs (`beast doctor`: `clock.ntp`).
- Wi-Fi keeps working even if the device gets renamed, because the profile has `connection.interface-name ""` (`beast install wifi`, §11.1).

## 3. Dual boot and the Ubuntu installer (§2)

1. In Windows, shrink `C:` (`nvme0n1p3`) to free space for Ubuntu.
2. Install **Ubuntu Desktop** (not Server, so the desktop stays as a fallback) with manual partitioning:
   - the free space → one **ext4** partition mounted at `/`
   - `nvme0n1p1` → reuse as the EFI System Partition (`/boot/efi`), **don't format it**
   - boot loader on `nvme0n1`; leave `nvme0n1p2`–`p4` alone; no swap partition (Ubuntu makes a swap file)
   - user `me`, hostname `beast`, password required at login
3. First boot: set `ubuntu` first in the BIOS boot order (step 1).

Then run the installer from the [README](../README.md).

## 4. On the client (the Mac)

- **SSH key** (§5.2): `ssh-copy-id me@beast`. If `ssh-keygen` offers to overwrite an existing key, answer **n** and reuse it. beast won't turn off SSH passwords until the key is on the server.
- **Tailscale**: the Mac app signed in to the same account. MagicDNS makes the server reachable as `beast`.
- **Ghostty terminfo** (§7): `infocmp -x xterm-ghostty | ssh me@beast -- tic -x -`, or for every host, in Ghostty's config: `shell-integration-features = ssh-env,ssh-terminfo`.
- **Tailscale key expiry**: Admin console → Machines → beast → … → Disable key expiry (or let beast do it with `TS_API_TOKEN`).

## 5. Memory troubleshooting (§10, §12)

- If it won't boot after a memory change: **one stick, in DIMMA2**.
- **Wait up to 10 minutes** after any memory change or CMOS reset. The first boot retrains DDR5 and can stay black that long. Don't cut power early.
- **EZ Debug LEDs**: yellow DRAM flashing briefly at startup is training; red (CPU) and yellow (DRAM) alternating means memory training keeps failing (wrong slot or a bad stick). Try the other stick alone in DIMMA2.
