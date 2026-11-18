# NAND-only OS feasibility (assessment + safe design)

Status: assessment (2026-11-17). Not implemented. Answer to "can we hack a workaround so NAND
can host the OS": **yes for a minimal read-only system; no for full Debian, but the combined
design covers the interesting case.**

## Numbers

- NAND: 256 MiB total; mtd0 5 M (U-Boot), mtd1 5 M (kernel), mtd2 5 M (free),
  mtd3 ~185 M (9.2 M rescue + ~176 M free after our 16 M erase window), mtd4–6 stock.
- Minimal Debian (base) tarball ≈ 250–350 MB unpacked, **does not fit**.
- A buildroot/BusyBox-style OS or a **Debian-minimal squashfs** (~60–120 MB compressed)
  **fits** in the mtd3 remainder (~176 M) with room to spare.

## What makes NAND-root workable

1. **Kernel already boots from mtd1 with our NAND DTS fix**, Linux sees mtdblock devices,
   so `root=/dev/mtdblockX` (or UBIFS) is reachable without USB.
2. **squashfs is read-only**, perfect for an unattended appliance root; config/state go to
   a small writable layer (UBIFS volume or USB overlay).
3. Current U-Boot bootargs use `root=PARTUUID=...`; a NAND-OS boot needs its own bootcmd
   (e.g. `nand read` kernel is unchanged; pass `root=/dev/mtdblock3 rootfstype=squashfs`).
   Keep the stock/USB bootcmd as the default and add the NAND-OS as a **manual/fallback
   boot path** (or U-Boot env fallback script), not the default.

## Proposed design (when we want it)

| Piece | Choice |
|---|---|
| Kernel | unchanged 6.12.117-wdnas (needs CONFIG_SQUASHFS=y + MTD block, verify in config) |
| Root | squashfs image flashed to mtd3 offset 0x1000000 (after rescue), ~60–120 M |
| State | optional UBIFS volume in remaining mtd3 or USB overlay (upperdir) |
| Boot | U-Boot: default = USB Debian (today); `run wdrescue` = rescue; new `run wdnandos` = squashfs boot |
| Safety | rescue stays at mtd3 offset 0; squashfs never overlaps it; erase windows sized separately |

## Risks / notes

- **Write endurance is irrelevant for squashfs** (read-only), this is the key insight that
  makes NAND-OS viable; never put journalling ext4 on raw NAND.
- Bad block at `0xff00000` is at the far end; mtd3 usable region is clean (checked 2026-11-17).
- mtd4–6 (stock rescue/config) stay untouched.
- USB-rootfs remains the normal OS; NAND-OS is the "no-USB fallback appliance mode", pairs
  with the rescue auto-reboot timeout (if USB is dead: rescue → fix or boot NAND-OS).
- Decision: implement only after the installer/release milestone; not needed for daily use.

## Verdict

- Full Debian on NAND: **not feasible** (256 M chip).
- Minimal read-only appliance OS on NAND: **feasible and safe** with the layout above.
- Current architecture (NAND kernel + USB rootfs + NAND rescue) remains the right default.

## IMPLEMENTED: NAND initramfs appliance (2026-11-17), WORKS
The read-only "appliance" fallback is implemented and hardware-verified.

- **Layout (local DTS only, not the upstream patch)**: stock `image.cfs` split into a
  9.25 MiB rescue slot (`0xf00000`) + **`appliance` partition `0x1840000` size `0x5400000`
  (84 MiB)**. Stock mtds renumber (appliance = mtd4).
- **Why initramfs, not squashfs-on-mtdblock**: Linux on this board reads NAND with
  BCH `ecc_strength=16/step=2048` while the stock U-Boot uses a different layout, so
  U-Boot-written pages are unreadable by Linux (`I/O error, dev mtdblock4`, 2148 ECC
  failures). Linux's own NAND writes also didn't verify (`nanddump` mismatch). So the
  appliance image is **read only by U-Boot** and unpacked to RAM by the kernel.
- **Image**: `uImage-wd-appinst` (9,652,938 B, `0x934aca`, sha256 `93722ad5…`):
  kernel + embedded initramfs (busybox, mtd-utils, e2fsprogs, mdadm, smartmontools,
  dropbear) + appliance DTB. Built by `rescue/build-appliance-initramfs.sh`.
- **Flash**: U-Boot `nand erase 0x1840000 0xa00000` + `nand write 0xa00000 0x1840000 0x934aca`.
- **Boot**: `wdnandos` env =
  `nand read 0xa00000 0x1840000 0xa00000; setenv bootargs console=ttyS0,115200; bootm 0xa00000`.
- **Runtime**: ro root is the initramfs (ramfs); `/etc,/var,/run,/tmp` are tmpfs;
  `/etc.defaults` is the source. Key-only Dropbear on :22 (use `~/.ssh/wd_key`),
  read-only HTTP backchannel on `:8098` (`status.json`, `events.log`), and the standard
  diagnostics. `reboot` (busybox) returns to the USB Debian.
- **Costs/limits**: ~10 MiB RAM for the unpacked initramfs; no RAID assembly
  (read-only diagnostics by design); not a full OS, it's the recovery/fallback shell.
