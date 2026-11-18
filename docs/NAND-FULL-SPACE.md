# Using the whole NAND, investigation log

Status: **appliance works (initramfs); squashfs/UBI blocked by a +1-byte Linux NAND read shift**
(2026-11-17). Every number below was measured on the device.

## Hardware (this unit)
- NAND: **Hynix H27U2G8F2CTR-BC**, 256 MiB SLC, **2048 B page, 64 B OOB, 128 KiB erase**.
  Bad blocks: only `0xff00000 … 0xffe0000` (last 8 eraseblocks, BBT area).
- SoC: Marvell Armada 370 (88F6710), NFCv1? (driver reports `pxa3xx_nand-0`), mainline
  `marvell_nand`.
- Stock U-Boot: **2011.12** (Marvell BSP), `bootdelay=3` now, UART recovery via **kwboot**
  proven possible on this board (see WD community unbrick thread).

## Partition map
```
mtd0 0x000000 5 MiB   u-boot
mtd1 0x500000 5 MiB   uimage      (normal Debian kernel, bootcmd reads this)
mtd2 0xa00000 5 MiB   ramdisk     (unused)
mtd3 0xf00000 9.25 MiB image.cfs  (rescue image at offset 0; stock was 201 MiB)
mtd4 0x1840000 84 MiB appliance   (our new partition: appliance image at offset 0)
mtd5 0xdd00000 15 MiB rescue-firmware (stock, restored)
mtd6 0xec00000 20 MiB config
mtd7 0xd800000 5 MiB  reserve
```

## What works
- **NAND initramfs appliance**: `uImage-wd-appinst` (kernel+initramfs, 9,653,506 B =
  `0x934d02`, sha256 `50c33945…`) at **0x1840000**; booted by U-Boot only
  (`wdnandos`), kernel unpacks to RAM. SSH key-only (`~/.ssh/wd_key`), HTTP backchannel
  `:8098`, `reboot` applet returns to the USB Debian. `panic=10` auto-recovers failures.

## Why squashfs-on-NAND / UBI does not work (yet)
1. **U-Boot↔Linux ECC incompatibility.** U-Boot-written pages are unreadable by Linux:
   `I/O error, dev mtdblock4, sector 0`, `ecc_failures=2148`, squashfs "unable to read
   superblock". The driver forces hardware `ecc_strength=16` and picks a layout from
   `marvell_nfc_layouts[]` by the DT strength (4/512 here), U-Boot 2011.12 uses a
   different OOB/ECC layout. `nand-ecc-mode = "none"` removes ECC failures
   (`ecc_strength=0`, `ecc_failures=0`) but…
2. **Linux NAND reads are shifted by exactly +1 byte** (global, not per page):
   - file off `2048` = `d4 25 c1 d0…`; Linux `/dev/mtdblock4` off `2048` = `25 c1 d0 ff…`
     = file off **2049**; Linux `4096` = file **4097**.
   - After `ubiformat` (a pure **Linux** write), raw `/dev/mtd4` reads
     `42 49 23 01…` where the EC header must be `55 42 49 23` ("UBI#"), again +1.
   So writes land correctly, **reads start one byte late**. U-Boot reads the same flash
   correctly (`md` → `hsqs`), so the image on flash is fine.
3. **UBI test results:** `ubiformat /dev/mtd4` succeeded (all 672 eraseblocks, Linux
   erase/write works), but `ubiattach -m 4` (and `-O 2048`) fails:
   `ubi_read_volume_table: the layout volume was not found`, `failed to attach mtd4,
   error -22`, exactly the +1 read shift.
4. Padding the squashfs with 1 leading byte (to compensate) still failed with
   `error -5` (mtdblock EIO / bad-block-map interaction).

## External evidence that the goal is achievable
- **OpenWrt merged WD MyCloud EX2 Ultra support** (Armada 385, **same H27U2G8F2CTR-BC**),
  using a **185 MiB "ubi" partition** written from Linux (`ubiformat`, `nandwrite
  --markbad`) with the stock U-Boot booting. (Different SoC/U-Boot ECC.)
- **linux-mtd thread (Dec 2020) is this exact device**: "WD MyCloud Ex, Armada-370,
  pxa3xx-nand, marvell-nfc". Miquèl Raynal listed 8 fixes for read-logic regressions:
  `f6997bec6af4 b76401fc4ba7 a2ee41fd953e 90d617633368 7fd130f7416f 53c83b59759c
  cafb56dd741e c27075772d1f`, all present in 6.12, so our +1 shift is a different
  (layout/OOB) issue.

## Next steps to unlock full NAND (ordered by risk)
1. **Try another LTS kernel** (5.10 or 6.1) with the same DTS, cheap to test in RAM;
   the read path differs between versions and this may be a 6.12-specific issue.
2. **Instrument/patch `marvell_nand.c`** read path: compare `data_off_in_page`
   computation and `nand_change_read_column_op(..., chunk * (data+spare+ecc))` against
   the chip's real layout (2048 data + 62 used OOB bytes of 64). A 1-byte start offset
   suggests a column/offset miscalculation in this configuration.
3. **Mainline U-Boot** (armada-370 board DTS + kwbimage), would make ECC/layout
   mainline-consistent and enable UBI natively; recoverable via kwboot if it fails
   (proven on this board), but still the highest-risk step.
4. Once reads align: `ubiformat` + UBI volumes → **"appliance" (squashfs via ubiblock)**
   + **"data" (UBIFS, writable)** → ~84 MiB (or expand into the old image.cfs region for
   ~185 MiB).

## Capacity answer
- Today: NAND holds the kernel (5 MiB) + rescue (9.25 MiB) + **appliance (10 MiB, working)**.
- With UBI unlocked: **~84 MiB** (appliance + data) immediately, **up to ~185 MiB** if the
  full image.cfs span is repartitioned.
- Without fixing the read path: no further NAND storage is usable (writable NAND from
  Linux is not trustworthy on this stock U-Boot).

## FINAL EXPERIMENT MATRIX (2026-11-17, all measured on hardware)
| Attempt | Result |
|---|---|
| U-Boot writes image → Linux BCH reads | ❌ EIO (`ecc_failures=2148`) |
| U-Boot writes image → Linux ECC-none reads | ⚠️ data readable but **+1-byte shifted** |
| Linux (BCH) `nandwrite` padded image | ❌ **EINVAL partway** ("Data was only partially written") |
| Linux (ECC-none) `nandwrite` padded image | ✅ writes, no bad blocks, shift compensated, but ❌ **xz decompress fails near the end** (no bitflip correction on old SLC) |
| UBI (`ubiformat` ok) → `ubiattach` | ❌ `layout volume was not found` (the +1 shift) |

**Verified details:**
- Read shift is **uniform +1 byte**: mtd4[N] == file[N+1] at offsets 0, 64, 2048, 4096, 8192.
- Padded image (1 leading byte) makes the *first* 64 KiB byte-identical, so the shift is fully
  compensable, but with ECC enabled writes abort (EINVAL) and with ECC disabled old-SLC
  bitflips corrupt compressed blocks.
- ECC enabled: `ecc_strength=16` (hardware BCH; DT strength 4 only selects the layout).
- Bad blocks: 0 in the appliance partition; the BBM area is only confused when *U-Boot*
  wrote the pages.

**Conclusion:** full-NAND (squashfs/UBI) needs one of:
1. another kernel line (5.10/6.1 LTS) - the linux-mtd thread for this exact board
   converged on 5.10; cheapest next test, RAM-boot only;
2. a `marvell_nand` fix for this SoC/layout (read +1, write EINVAL);
3. mainline U-Boot (armada-370 DTS + kwbimage) - recoverable via kwboot, highest effort.
Until then the **NAND initramfs appliance** is the correct, proven design.

## BREAKTHROUGH: kernel 5.10.109 fixes NAND I/O, full NAND now usable (2026-11-17)
The `marvell_nand` userspace I/O bugs (read +1 byte, BCH write EINVAL) are **6.12-specific**.
A stock **linux-5.10.109** built with the same appliance DTS works perfectly:

- `ubiformat /dev/mtd4` -> OK; **`ubiattach -m 4` -> OK** (672 LEBs, 81.3 MiB, LEB 126976 B,
  VID offset 2048, data offset 4096);
- `ubimkvol` + `mount -t ubifs` -> OK; 4 MiB random file: write -> sync -> umount ->
  remount -> **identical sha256** (`fbc00cf7…`) => persistent writable NAND works;
- `ubi.mtd=4` on the kernel cmdline auto-attaches UBI at boot;
- **UBIFS root boots**: `root=ubi0:rootfs rootfstype=ubifs init=/init` (needs `rw` for a
  writable root; without it the appliance init cannot create `/www`).

### Final NAND layout (current)
```
mtd4 "appliance" 84 MiB = UBI container
  ubi0:rootfs  40 MiB (320 LEBs)  UBIFS, writable appliance root (8.3 MiB used)
  ubi0:data    32 MiB            UBIFS, writable storage
```
Kernel: build `linux-5.10.109` with `MTD_RAW_NAND=y MTD_NAND_MARVELL=y MTD_BLOCK=y
SQUASHFS=y MTD_UBI=y MTD_UBI_BLOCK=y UBIFS_FS=y` (`uImage-wd-510`, 4,308,530 B =
`0x41be32`). Keep the **normal OS on the 6.12 kernel** (its modules live on the USB
rootfs); use 5.10 only for the NAND appliance. Boot command:
`ubi.mtd=4 root=ubi0:rootfs rootfstype=ubifs init=/init rw panic=10`.

### Building the UBIFS volume contents
```
mkfs.ubifs -r /tmp/appliance-root -m 2048 -e 126976 -c 330 -x none -o rootfs.ubifs
ubimkvol /dev/ubi0 -N rootfs -s 40MiB
ubiupdatevol /dev/ubi0_0 rootfs.ubifs
ubimkvol /dev/ubi0 -N data -m
```
(`-m` = page size 2048, `-e` = LEB 126976, `-c` = max LEB count for the volume.)

### Capacity gained
From "kernel only" to **72 MiB usable NAND** (40 rootfs + 32 data) today, expandable to
~180 MiB by moving the partition boundary over the old `image.cfs` span.

## FINAL STATE, 191 MiB partition, 185.7 MiB UBI (2026-11-17 17:1xZ)
- Appliance partition corrected to **`0x1840000` size `0x0BFC0000`** (191 MiB, ends exactly
  at the stock `0xD800000` boundary). NOTE: an earlier value of `0x0C640000` extended to
  `0xDE80000` and **overlapped the stock rescue region at 0xdd00000**, where the appliance
  kernel lived, ubiformat wiped it. Fixed.
- UBI: **185.7 MiB** total (1534 LEBs), volumes:
  - `rootfs` 40 MiB → 35.2M visible, 8.2M used (UBIFS, **rw** root; 27M free)
  - `data` 140.3 MiB → **127.9M visible, 123.2M free** (UBIFS, rw)
- Verified: SSH key-only, backchannel `:8098`, file write+read on `/data`, remount
  persistence (32 MB random file, identical sha256 after umount/mount).
- Root-image ownership matters: build the rootfs tarball with `--owner=0 --group=0`
  (mkfs.ubifs preserves build-user uid otherwise, and Dropbear then rejects
  `/root/.ssh`); the appliance init also runs `busybox chown -R 0:0 /root`.
- Boot chain (saved U-Boot env):
  - `bootcmd_main = nand read.e 0xa00000 0x500000 0x500000 ; bootm 0xa00000`
  - `bootcmd = if run bootcmd_main; then true; else echo USB_KERNEL_LOAD_FAILED; run wdnandos; fi`
  - `wdnandos = nand read 0xa00000 0xdd00000 0x500000; setenv bootargs console=ttyS0,115200 ubi.mtd=4 root=ubi0:rootfs rootfstype=ubifs init=/init rw panic=10; bootm 0xa00000`
  - `bootdelay=3`
- **Research lead not yet tested**: the Seagate Armada-370 board DTS uses
  `marvell,nand-keep-config` (keeps U-Boot's NAND timings). We lack it. If adding it fixes
  the 6.12 read-shift/EINVAL, the normal kernel could host the UBI too (single kernel).

## ROOT CAUSE FOUND, `marvell,nand-keep-config` (2026-11-17 17:4xZ)
Driver diff `5.10.109` vs `6.12.117` (`/tmp/marvell_nand_510_vs_612.diff`) revealed:
1. **Inverted default**: 5.10 did `if (!of_property_read_bool(np,"marvell,nand-keep-config"))
   options |= NAND_KEEP_TIMINGS;`, i.e. it kept bootloader timings **by default**.
   6.12 only keeps them **when the property is present**. Our DTS lacked it, so 6.12
   reprogrammed the NFC timings → corrupted reads (+1-byte shift) and failed writes.
2. 6.12 additionally checks chip-side write status (`nand_status_op` → `-EIO` on
   `NAND_STATUS_FAIL`), which surfaced the failure instead of hiding it.

**Adding `marvell,nand-keep-config;` to `nand@0` fixes 6.12 completely:**
- read `/dev/mtd4` → `55 42 49 23` ("UBI#"), no shift;
- 4 KiB random write → read-back identical (`14f9a598…`);
- the existing UBI attaches, both UBIFS volumes mount, cross-boot persistence works.

**Result: one kernel for everything.** `uImage-wd-612-final` (6.12.117-wdnas #24,
4,911,799 B = `0x4AF2B7`, NAND+UBI+UBIFS+squashfs built-in, big-keepcfg DTB, no
initramfs) is flashed to **both mtd1** (normal OS, USB root) **and `0xdd00000`**
(appliance, UBIFS root). The 5.10 kernel is no longer needed.
The property is also added to the **upstream DTS patch** (checkpatch 0 errors).
