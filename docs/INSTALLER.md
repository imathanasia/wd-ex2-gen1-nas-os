# Installer / first-run experience (NAND boot manager + web setup)

Status: **Phase 1 implemented and verified on hardware** (2026-11-17). Basis: the NAND appliance is a full
6.12 kernel + UBIFS root, the *same kernel* as the installed Debian, so it can act as a
boot manager and hand off with `switch_root` (no initramfs/kernel mismatch).

## Goal (user's spec)
Sell/redeploy the box with no OS: plug in disks, power on, and a **web page** (reachable by
DHCP) tells the user to insert a USB 3.0 stick (or pick a disk) for the OS and disks for
data, then installs Debian. The flow mirrors a standard NAS installer.

## Architecture
```
U-Boot (bootdelay=3)
 ├─ bootcmd → mtd1 kernel → installed OS on USB/SATA (current, proven)
 └─ fallback/`run wdnandos` → NAND appliance kernel + UBIFS root (boot manager)
        ├─ probes block devices for an installed root (ext4 with /sbin/init)
        ├─ FOUND   → mount rw, exec switch_root <dev> /sbin/init   → normal OS
        └─ NOT FOUND → setup mode:
              • DHCP/static network
              • busybox httpd on :80  (setup page, DSM-styled)
              • backchannel :8098 (status.json)
              • serial shell
              • Phase 2: choose target disk → partition (MBR) → mkfs.ext4 → unpack
                rootfs tarball (shipped in /data) → set boot → reboot
```
Why the appliance can switch_root: both boots run the **same 6.12.117 kernel** (unified
build `uImage-wd-612-final`), so the installed root's `/lib/modules` matches. The kernel
cmdline (`root=`) is irrelevant after switch_root.

## Boot-manager logic (Phase 1, in `/init`)
1. mount proc/sys/devtmpfs, tmpfs layers (only when running from UBIFS: `/` is already rw).
2. **Probe**: for each `/dev/sd[a-z][0-9]`, try `mount -t ext4 -o ro`; accept if
   `/sbin/init` or `/init` exists (and optionally `/etc/debian_version`).
3. Found → `mount -o remount,rw`, `exec switch_root /newroot /sbin/init`.
   Escape hatch: `/data/no-autoboot` or kernel arg `wdnosetup=1` forces setup mode.
4. Not found → setup mode (web + backchannel + serial shell), print instructions.

## Phase 2 (installer), design
- Setup page lists block devices (size/model) read from `/sys/block`, asks:
  target for OS (USB stick recommended) + optional data disks, confirmation text.
- Installer script runs server-side via CGI (`busybox httpd` CGI) with progress streamed.
- Steps: wipefs → sfdisk (MBR, one Linux partition, LABEL=rootfs) → mkfs.ext4 →
  mount → untar the shipped rootfs (`/data/rootfs.tar.gz`) → fstab (PARTUUID) →
  optional mdadm RAID1 for data → sync → reboot.
- Rootfs tarball ships in the 128 MiB `data` volume.

## Visual language

The installer uses a dark, high-contrast console style with large touch targets and
a clear confirm step. All CSS is project-owned.

## Test matrix
| Case | How |
|---|---|
| Installed OS present | boot appliance → switch_root → normal Debian (must reach services) |
| No OS | temporarily rename the rootfs label / unbind USB → setup page on :80 |
| Escape hatch | `touch /data/no-autosetup` → setup mode even with an OS |

## Open questions
- Does `poweroff` cut power? (gpio-poweroff/MCU), affects "install done → power off".
- Boot order: make the appliance the default boot (so a missing OS is graceful) or keep the
  direct mtd1 boot primary? Current: direct primary + fallback on load failure.

## Phase 1 result (verified on hardware)
```
WD NAND boot manager - wdmycloud
boot-manager: block devices: /dev/sda /dev/sdb /dev/sdc /dev/sdc1
boot-manager: installed OS on /dev/sdc1 -> handing off
boot-manager: pivot_root done, starting OS init
→ systemd boots; root=/dev/sdc1; all services active
```
Two bugs found and fixed during bring-up:
- `switch_root` refuses a non-initramfs old root → use **`pivot_root`**
  (`pivot_root /newroot /newroot/.oldroot` then `chroot . /sbin/init`), with a
  `reboot -f` fallback that lands in the OS via U-Boot `bootcmd`.
- `/sbin/init` is an **absolute symlink** on Debian; detect the installed OS with
  `/etc/debian_version` / `/usr/sbin/init` instead.
- `/etc` must be seeded from `/etc.defaults` on the UBIFS root (Dropbear needs
  `/etc/passwd`).
- Wait for USB/SATA enumeration (up to 20 s) before probing.

## Phase 2: installer implemented (dry-run verified)
- `/` on :80 already serves a DSM-styled setup page with a live disk list.
- Add: disk picker (target OS disk vs data disks), confirmation gate, then
  wipefs → sfdisk (MBR, LABEL=rootfs) → mkfs.ext4 → untar `/data/rootfs.tar.gz` →
  fstab by PARTUUID → optional mdadm RAID1 for data → sync → reboot.
- Rootfs tarball ships in the 128 MiB `data` volume.

## Phase 2 result (2026-11-17, dry-run verified)
`/cgi-bin/install` (busybox httpd CGI in setup mode) now:
- validates the target (refuses mtd, mounted, root, and RAID members) and prints a plan;
- requires `confirm=ERASE`; `dry=1` writes nothing (verified on hardware);
- finds the source in `/data/rootfs.tar.gz|.xz`, any mounted disk, or `src=<url>`;
- verifies `<src>.sha256` when present (warns when absent);
- real run: 2 MiB zero wipe -> scripted `busybox fdisk` MBR -> `mke2fs -t ext4 -L rootfs`
  -> mount -> untar -> `/etc/fstab` by PARTUUID -> optional `mdadm` RAID1 + `mkfs` `nas`
  -> sync. Uses busybox + e2fsprogs (`mke2fs` staged into the appliance).
- Boot manager unmounts the old root after `pivot_root` (it was holding the UBI device).

### Rootfs source sizing (open decision)
`/data` is 128 MiB; a Debian 12 armhf rootfs tarball is typically 150-250 MiB xz, so it
does not fit. Options:
1. **Install from a USB stick** (rootfs.tar.xz on it) - no size limit. Recommended.
2. **Network install** (`src=<url>`), needs internet.
3. Shrink the appliance `rootfs` volume (40 -> 24 MiB) -> `/data` ~144 MiB - still tight.

## Test matrix
| Test | Result |
|---|---|
| dry-run: target + plan + source + integrity | PASS (2026-11-17) |
| real install to a spare USB/SATA | pending (needs a spare disk) |
| post-install boot via boot manager | pending |
