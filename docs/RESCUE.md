# Rescue / initramfs architecture (implemented & tested)

Status: **implemented and tested on hardware (2026-11-17)**. Rescue kernel with embedded
initramfs + NAND built‑in boots from NAND mtd3, runs the ASCII MOTD, network, diagnostics,
backchannel (`:8098`), and a shell. It listed all mtd0–mtd6 partitions and mtdblock devices.
Normal Debian also has NAND (`/dev/mtd1`). This is the “always recoverable” layer when USB
rootfs/kernel modules/normal boot fail.

**Tested rescue:** `uImage-rescue-tools` (9,640,930 bytes = `0x931be2`, sha256
`83c3554ecc9dfc491d3b8329a4968806d204b7bf8aa61a1b8d84637caec05829`), key-only Dropbear SSH (`-R -s`),
5-minute no-session auto-reboot to normal OS (touch `/tmp/noautoreboot` to disable),
mtd-utils + e2fsprogs + mdadm + smartmontools bundled. Stored in mtd3 at offset 0. U‑Boot:
```
nand erase 0xf00000 0x1000000   # erase window MUST cover the full image
nand write 0xa00000 0xf00000 0x931be2
nand read 0xa00000 0xf00000 0x931be2
bootm 0xa00000
```
End-to-end verified: with no SSH session, the rescue logs
`no rescue session after 5min; rebooting to normal OS` and returns to Debian by itself
(verified: back in normal OS ~345 s after boot).
If the erase window is smaller than the image, the tail is written over non‑erased pages and the
readback fails `Bad Data CRC`; stock U‑Boot then falls back to the stock rescue firmware (mtd4,
Linux 3.2.40), which cannot enumerate the USB3 rootfs stick.
Separate uRamdisk cpio did not unpack on this U‑Boot/kernel combo (old ext2-initrd path);
embedding via `CONFIG_INITRAMFS_SOURCE` is the reliable method. `mtd2` is only 5 MiB, too
small for this 6.74 MiB kernel image.

## Principles

1. **Independent of the USB rootfs.** Rescue lives in NAND/initramfs or can be TFTP-booted.
2. **Read-only by default.** No automatic RAID assembly, no auto-mount of RAID members, no
   writes unless explicitly forced.
3. **Observable.** Serial console + SSH + a universal HTTP backchannel.
4. **Boring and tested.** Minimal userspace, key-only SSH, LAN-only, no cloud.
5. **Two ways in:** serial (always) and network (DHCP/static + SSH).
6. **Safe fallbacks:** stock NAND images, TFTP images, USB rescue stick.

## Boot paths

| Path | What | When |
|---|---|---|
| Normal | U-Boot → NAND kernel/DTB → USB rootfs → systemd | everyday |
| Rescue NAND | U-Boot → kernel + **initramfs in mtd2** (`uRamdisk`) | USB rootfs missing/broken |
| Rescue TFTP | U-Boot → TFTP kernel + initramfs (no NAND write) | before flashing / experiments |
| Rescue USB | U-Boot → USB FAT32 initramfs | if NAND is suspect |
| Last resort | serial U-Boot prompt, TFTP reflash | bootloader still works |

The stock U-Boot can boot a kernel + separate ramdisk:

```
tftp 0xa00000 uImage-rescue
tftp 0xf00000 uRamdisk-rescue
bootm 0xa00000 0xf00000
```

Keep the stock `uRamdisk` and NAND backups; never overwrite mtd0.

## Rescue initramfs contents

Keep it small enough for mtd2 (~5 MiB compressed). Priorities:

- **BusyBox** (static): `sh`, `mount`, `fsck`, `dd`, `nc`, `wget`, `vi`, `top`, `ps`,
  `dmesg`, `ip`/`ifconfig`, `udhcpc`, `mdev`, `tar`, `gzip`.
- **Dropbear SSH** (keys generated at build; key-only root login).
- **mtd-utils**: `flash_erase`, `nandwrite`, `nanddump`, `mtd_debug`.
- **e2fsprogs**: `e2fsck`, `resize2fs`, `dumpe2fs` (read-only checks first).
- **mdadm** (optional, read-only assemble with explicit config; never bare `--scan`).
- **smartmontools** (SMART health; `-n standby` to avoid waking disks).
- **curl/wget**, `jq` (if size allows), `tmux`/`screen` optional.
- **Backchannel** script + tiny HTTP server (BusyBox `httpd` CGI or static JSON).
- `/etc/motd`, `/etc/issue`, SSH banner, ASCII art.
- Kernel modules needed for USB/xHCI, ext4, md, SATA (or use a kernel with them built in).

If the full toolset exceeds the 5 MiB mtd2 budget, split:

- **mtd2**: tiny network/serial rescue (BusyBox + dropbear + backchannel).
- **USB/TFTP**: full toolkit (mtd-utils, e2fsprogs, smartmontools, logs).

## Universal backchannel (portable)

A read-only JSON + log channel that any future host/client can poll. Works in rescue and in
the normal OS.

- **State file**: `/run/wd/backchannel/status.json` (tmpfs) + `/run/wd/backchannel/events.log`.
- **HTTP**: `:8098` (rescue) or normal `status.json` on the NAS web server.
- **Serial**: same lines also go to `ttyS0` with a `WDBC:` prefix.
- **Fields** (stable contract):

```json
{
  "schema": "wd-backchannel/1",
  "host": "wdmycloud",
  "mode": "normal|rescue|tftp",
  "stage": "boot|network|storage|ready|error",
  "kernel": "6.12.117-wdnas",
  "uptime_s": 42,
  "network": {"eth0": "192.168.1.22/24", "gw": "192.168.1.1", "dhcp": false},
  "storage": {"usb_rootfs": "sdc1|missing", "md0": "UU|unknown", "disks": ["sda","sdb"]},
  "tests": {"serial": "ok", "ssh": "ok", "backchannel": "ok", "nand": "probe-error"},
  "artifacts": {"uImage": "sha256:...", "initramfs": "sha256:..."},
  "last_error": null,
  "remediation": ["try other USB port", "power cycle with stick inserted"]
}
```

- **Endpoints** (rescue HTTP): `/status.json`, `/log` (text tail), `/health` (plain), `/`.
- **Security**: LAN-only, no write endpoints, no secrets, optional bearer token; SSH key-only.
- **Usage**: poll `curl http://<nas>:8098/status.json`, tail serial, or read
  `events.log`; no need to guess boot state.

This pattern is deliberately portable: same JSON schema on Debian, rescue initramfs, and any
future NAS/board.

## ASCII MOTD / issue

```text
   __        __ ___    _   _    _    ____
   \ \      / /| _ \  / \ | |  / \  / ___|
    \ \ /\ / / | | | |/ _ \| | / _ \ \___ \
     \ V  V /  | |_| / ___ \ || (_) | ___) |
      \_/\_/   |____/_/   \_\_\___/ |____/

            R E S C U E   M O D E
      WD My Cloud EX2 Gen1  ·  ImAthanasia
   serial 115200 8N1  ·  ssh root@192.168.1.22
        (^ω^)   no data was touched
```

Also print kernel, disk presence, md0 state, network, and a one-line hint list.
Keep the same credit line in `/etc/issue`, `/etc/motd`, hub, GitHub and the kernel build
banner.

## Hard safety rules (from WD experience)

- Never mount `/dev/sda2` / `/dev/sdb2` directly; only `/dev/md0`, and only read-only in rescue.
- Never `mdadm --scan` without an explicit config; it can probe NAND and freeze devices.
- Never format/auto-add RAID members. Show serials first.
- Never write NAND unless the user explicitly asks; back up first (`nanddump`).
- Do not send unknown MCU/UART commands. Fan is GPIO (`gpio-fan`); power LED is `a3g` MMIO.
- Rescue must not auto-wake sleeping disks (`smartctl -n standby`, `hdparm -C`).

## Build pipeline (planned)

```text
rescue/
  build-initramfs.sh      # cross-armhf: busybox/dropbear/tools -> cpio.gz
  files/                  # motd, issue, init, backchannel, ssh keys
  test-qemu.sh            # generic boot/SSH/backchannel smoke test
  README.md
```

Steps:
1. Build/obtain static BusyBox + Dropbear + tools for armhf; assemble rootfs.
2. `find . | cpio -o -H newc | gzip > uRamdisk-rescue`.
3. Test via **TFTP first** (`tftp ... uRamdisk-rescue` + `bootm`), serial + SSH +
   backchannel + `/proc/mtd` + read-only storage checks.
4. Only after tests: backup mtd2, write rescue (`flash_erase /dev/mtd2` + `nandwrite`), keep
   stock `uRamdisk` in `nand-backup/`.
5. Document SHA-256 and rollback in NOTES/RECOVERY.

## Test matrix (must pass before flashing)

- Serial console login and MOTD/ASCII.
- DHCP fallback to static 192.168.1.22; SSH key-only.
- Backchannel `/status.json` valid and reachable.
- `/proc/mtd` shows NAND partitions (kernel + modules).
- `smartctl -n standby` and `mdadm --detail /dev/md0` read-only.
- Read-only fsck/dumpe2fs on USB; no automatic mount of RAID members.
- Power loss / reboot returns to normal OS (rescue does not change U-Boot env).
- NAND write tools present but disabled by default.

## Current status (verified)

- **Rescue kernel with full tool bundle flashed to mtd3 and boot-tested (2026-11-17)**:
  TFTP RAM test first, then mtd3 boot. Verified: ASCII MOTD, network, diagnostics, mtd0–mtd6,
  backchannel `:8098/status.json` (live symlink, self-refreshing), key-only SSH
  (`dropbear -R -s`), and the read-only tool smoke test (all tools PASS; md0 correctly NOT
  assembled; SMART with `-n standby` PASSED on both disks).
- Tool staging: `rescue/stage-tools.sh` runs on the NAS, exports binaries + `ldd` closure
  (chroot-validated) to `wd-tools.tar.gz`; `build-initramfs.sh` unpacks it (env `TOOLS_TAR`,
  `AUTHORIZED_KEYS`). Dropbear has no scp/sftp, pipe files over ssh (`cat > file`).
- Boot fallback: if the embedded initramfs fails to unpack, the rescue kernel falls back to
  `root=PARTUUID=b07640b0-01` and boots the normal USB Debian (rescue kernel == normal kernel).
- Previous images kept at `/srv/nas/backups/rescue/` (`uImage-rescue-nand`, `-ssh`);
  `uImage-rescue-tools` is the current one.
