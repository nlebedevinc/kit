# beast: manual steps before kit

kit starts from a fresh Ubuntu Desktop. These steps come first and can't be scripted.
Source: [SETUP-LOG.md](SETUP-LOG.md) §1–2.

## 1. Firmware (MSI BIOS)

MSI keys: **Delete** = BIOS, **F7** = Advanced Mode, **F10** = save and exit, **F11** = one-time boot menu.

- **XMP → Profile 1**, so the RAM runs at its rated DDR5-6000.
- After installing Ubuntu (step 3): put the **ubuntu** UEFI entry **first** in the boot order.

## 2. Make room next to Windows (single 2 TB drive)

Factory layout:

| Partition | Type | Size | Role |
|---|---|---|---|
| `nvme0n1p1` | vfat | ~105 MB | EFI System Partition ("Windows Boot Manager") |
| `nvme0n1p2` | — | ~17 MB | Microsoft Reserved |
| `nvme0n1p3` | NTFS | 2.00 TB | Windows `C:` |
| `nvme0n1p4` | NTFS | 524 MB | Windows Recovery |

Shrink `nvme0n1p3` (Windows `C:`) from Windows Disk Management to free space for Ubuntu.

## 3. Install Ubuntu Desktop (manual partitioning)

- **Edition:** regular **Ubuntu Desktop** (not Server), so a desktop stays available as a fallback. kit turns it off at boot later.
- **Partitions:**
  - Free space → **one ext4 partition mounted at `/`**.
  - `nvme0n1p1` → **EFI System Partition (`/boot/efi`), do not format.** It's shared with Windows.
  - Boot loader location: **`nvme0n1`**.
  - Leave `nvme0n1p2`, `nvme0n1p3`, `nvme0n1p4` alone.
  - No swap partition (Ubuntu uses a swap file).
- **Account:** your user (the profile expects `me`) and hostname `beast`, password required at login.

## 4. First boot

If the machine boots straight into Windows and the firmware shows only "Windows Boot Manager", put the **ubuntu** entry first in the firmware boot order (step 1). Windows stays available with **F11 → Windows Boot Manager**.

## 5. Run kit

Log in to the desktop, connect to the network, open a terminal:

```bash
wget -qO- https://raw.githubusercontent.com/<github-user>/kit/main/install.sh | bash -s -- --host beast
```

(`curl -fsSL … | bash -s -- --host beast` works too once curl is installed.)

Before kit can turn off SSH password login, copy your key **from the client** (the Mac): `ssh-copy-id me@beast`. kit tells you when.
