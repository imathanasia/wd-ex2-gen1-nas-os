# USB install checklist, two sticks, both ports (2026-11)

Purpose: validate the setup-mode installer on real hardware without touching the
NAND appliance kernel or the existing root USB. Two sticks: **SOURCE** (rootfs
tarball) and **TARGET** (new OS). The NAND kernel (mtd1 + rescue copy at
0xdd00000) stays as-is.

## 0. What must be true before you start

- NAND appliance kernel is the unified 6.12 (`uImage-wd-612-final`, 4,911,799 B),
  flashed at **0x500000** and **0xdd00000**.
- Appliance rootfs contains the current installer (sha256 **cb0b09a8…**), the
  clock helper (**ff81495c…**) and `init` (**9e0619af…**). Verify after mounting
  mtd4 (see §7) or trust the last deploy log.
- Serial console works (`ttyS0`, 115200 8N1) and you can reach `http://<nas-ip>/`.
- Target stick ≥ 8 GB (extracted rootfs is ~1–2 GB; 4 GB is cutting it close).
- Source stick can be any size ≥ rootfs archive (~150–250 MB compressed).

## 1. Build the rootfs archive (on the working Debian system)

Run on a known-good rootfs (current USB root or a chroot copy), as root:

```sh
cd /
tar --numeric-owner --one-file-system -C / \
  --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run \
  --exclude=./tmp --exclude=./mnt --exclude=./media --exclude=./srv/nas \
  --exclude=./var/cache/apt --exclude=./var/lib/apt/lists \
  -czf /tmp/rootfs.tar.gz .
sha256sum /tmp/rootfs.tar.gz | cut -d' ' -f1 > /tmp/rootfs.tar.gz.sha256
```

Checks:
- `/etc/debian_version` **must exist** (boot manager uses it to recognise the OS).
- `/lib/modules/$(uname -r)` must match the NAND kernel you boot
  (`6.12.117-wdnas…`), otherwise no network/storage drivers after install.
- `/etc/fstab` is rewritten by the installer; contents do not matter.
- Do **not** include `/srv/nas` (RAID data stays on the disks).
- Prefer `.tar.gz` or `.tar.xz`; `.tar.zst` is refused by the appliance.

## 2. Prepare the SOURCE stick

- Format vfat, ext4 or exfat; label it e.g. `WDSRC`.
- Copy to the **root** (or one directory deep):
  - `rootfs.tar.gz`
  - `rootfs.tar.gz.sha256` (single line, hex digest only)
- Unmount cleanly. The installer mounts it **read-only** and scans `sd?[0-9]`.

URL alternative (no stick): `src=http://host/rootfs.tar.gz`, fetched into RAM
(`/tmp`, tmpfs) and verified. Requires network; the dead RTC is handled by
`/rescue/wd-setclock` + `--no-check-certificate` fallback.

## 3. Prepare the TARGET stick

- Any contents; it will be wiped. **Remove any other USB storage.**
- Insert into one of the two EX2 ports; note which port you are testing.

## 4. Enter setup mode

Setup mode is chosen when: `wdnosetup=1` in the kernel cmdline, or
`/data/no-autoboot` exists, or no bootable OS is found. For a forced run from
U-Boot:

```
setenv bootargs console=ttyS0,115200 ubi.mtd=4 root=ubi0:rootfs rootfstype=ubifs init=/init rw wdnosetup=1 panic=10
nand read 0xa00000 0xdd00000 0x500000
bootm 0xa00000
```

Watch serial for: `boot-manager: entering SETUP mode`, DHCP line, `setup UI:`.
The appliance also starts a clock sync in the background (`clock set to … UTC`).

## 5. Run the installer

1. Open `http://<nas-ip>/` (also `:8098/disks.txt` for the raw disk list).
2. Select the **TARGET** stick as OS disk; leave data disk empty (no RAID test in
   this pass). Do not select a stick that is mounted or a RAID member.
3. Tick **dry run**, type `ERASE`, submit. Expect:
   `DRY RUN - nothing written.`, `source disk: /dev/sdX`, plan lines.
4. Untick dry run, submit. Watch serial. Expected sequence:
   wipe → fdisk → mke2fs → mount → download (if URL) → SHA-256 OK →
   magic-byte untar → `fstab (UUID=…)` → `OS installed on /dev/sdX1`.
5. If the source is a stick, confirm `source disk: /dev/sdY` names the right port.

## 6. Verify the installed target

- Power off, remove the SOURCE stick, keep TARGET inserted.
- Cold boot (full unplug is the real test, RTC is dead, so check the clock too).
- Boot manager should find `/etc/debian_version`, `pivot_root`, then Debian boots.
- On the installed system:
  ```sh
  findmnt /            # expect UUID=… / ext4
  cat /etc/fstab
  ip -4 addr show eth0
  systemctl --failed
  wd-mcu              # MCU helper still responds/fire-and-forget
  ```
- Confirm the **NAND kernel** is running: `uname -r` = the 6.12 appliance build.
- Repeat the whole flow once per USB port (USB2/USB3) with a fresh target stick,
  or at minimum re-run dry-run in the second port.

## 7. Rollback / recovery

- Nothing on NAND is written by the installer. To go back: unplug the target
  stick, boot the original root USB.
- Stuck in setup mode: remove `/data/no-autoboot` (mount `ubi0:data`) or boot
  with `wdnosetup=0`.
- If setup UI is unreachable: serial shell is available; `:8098/disks.txt` gives
  the disk list; `/setup/cgi-bin/install` can be run by hand with the same
  QUERY_STRING.
- Last-resort NAND recovery unchanged: U-Boot `wdnandos` at 0xdd00000, or TFTP
  the rescue kernel to mtd3.

## 8. Record results

| Port | Source | Target | Clock sync seen | SHA OK | fstab UUID | Boot OK | Notes |
|---|---|---|---|---|---|---|---|
| USB2 |  |  |  |  |  |  |  |
| USB3 |  |  |  |  |  |  |  |

Known gotchas:
- USB3 enumeration can fail after warm reboot; cold power-cycle + reseat.
- Busybox `wget -T` **segfaults**, never add it back.
- Never select the stick that holds the source archive as target (installer
  refuses mounted devices, but double-check).
- `PARTUUID` is not available in the appliance (mdev); fstab uses ext4 `UUID=`.
