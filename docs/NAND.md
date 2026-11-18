# NAND access in Linux, fixed, validated, and rescue-aware

## STATUS: FIXED & VERIFIED (2026-11-17)

- Fixed DTB (`nand-controller@d0000` + child `nand@0`) flashed into mtd1 with the normal kernel.
- **Normal Debian now sees 7 MTD partitions** (`mtd0`–`mtd6`) and `/dev/mtd1`; `mtd3` is
  205,824 KiB. No NAND probe error.
- **Rescue kernel** (embedded initramfs + NAND built-in) boots from **mtd3** and lists all
  mtdblock devices; diagnostics/backchannel/ASCII MOTD work.
- mtd3 now holds the tool-bundle rescue kernel in its first `0x93175a` bytes (stock image.cfs
  was backed up in `nand-backup/mtd3.img`). U-Boot: erase `0xf00000 0x1000000` (16 MiB, must
  exceed the image), write, read-back (checksum must print OK), then
  `nand read 0xa00000 0xf00000 0x931be2 ; bootm 0xa00000`.
- Normal kernel rollback image remains `uImage-wd-final` (TFTP `o`); rescue image is also
  saved at `/srv/nas/backups/rescue/uImage-rescue-nand-ssh` (key-only Dropbear SSH).

## Historical symptom (before the fix)

```
marvell-nfc soc:internal-regs:nand@d0000: error -EINVAL: invalid resource (null)
marvell-nfc ... probe with driver marvell-nfc failed with error -22
```

No `/proc/mtd`, no `/dev/mtd1` in Debian. Booting from NAND still works because U-Boot reads
mtd1 itself; the kernel does not need the NAND driver to boot.

## Root cause

Mainline 6.12 uses a **controller + chip-child** model (see `armada-370-xp.dtsi`):

```dts
nand_controller: nand-controller@d0000 {
    compatible = "marvell,armada370-nand-controller";
    reg = <0xd0000 0x54>;
    #address-cells = <1>;
    #size-cells = <0>;
    interrupts = <113>;
    clocks = <&coredivclk 0>;
    status = "disabled";
};
```

Our Gen1 DTS defines a **legacy separate node** named `nand@d0000` with
`compatible = "marvell,armada370-nand"` but **no `reg` property**. The driver binds to that
node, asks the platform layer for its memory resource, gets `NULL`, and fails `-EINVAL`.
The partitions were also attached directly to the controller instead of a NAND chip child.

## Correct structure (gisab Gen1 board)

Use the mainline controller and a child chip node. Example:

```dts
&nand_controller {
    status = "okay";

    nand@0 {
        reg = <0>;
        label = "pxa3xx_nand-0";
        nand-rb = <0>;
        nand-on-flash-bbt;
        nand-ecc-strength = <4>;
        nand-ecc-step-size = <512>;
        /* optional: marvell,nand-keep-config; */

        partitions {
            compatible = "fixed-partitions";
            #address-cells = <1>;
            #size-cells = <1>;

            partition@0 {
                label = "u-Boot";
                reg = <0x00000000 0x00500000>;
                read-only;
            };
            partition@500000 {
                label = "uImage";
                reg = <0x00500000 0x00500000>;
            };
            partition@a00000 {
                label = "ramdisk";
                reg = <0x00A00000 0x00500000>;
            };
            partition@f00000 {
                label = "image.cfs";
                reg = <0x00f00000 0x0c900000>;
            };
            partition@dd00000 {
                label = "rescue firmware";
                reg = <0x0dd00000 0x00f00000>;
            };
            partition@ec00000 {
                label = "config";
                reg = <0x0ec00000 0x01400000>;
            };
            partition@d800000 {
                label = "reserve";
                reg = <0x0d800000 0x00500000>;
            };
        };
    };
};
```

Remove the old `nand@d0000 { ... }` node (or replace it entirely). Do not keep both.

Notes:
- `reg = <0xd0000 0x54>` (controller) and `reg = <0>` (chip select) are **different things**.
- The controller has `#size-cells = <0>`; the chip child has `reg = <0>` (CS 0).
- Keep `nand-on-flash-bbt`, ECC strength/step and partition labels exactly aligned with the
  existing flash layout. A wrong ECC/partition can make NAND unreadable from Linux.
- `nand-rb = <0>` is the ready/busy line index; use the board value (0 here).
- Kernel config needs `CONFIG_MTD_RAW_NAND=m/y` + `CONFIG_MTD_NAND_MARVELL=m/y`
  (and NAND core/ECC, which are built-in in our final image). `marvell_nand.ko` then probes.

## Why this is optional for boot

U-Boot owns mtd0/mtd1 and loads the kernel/DTB. Linux now also has NAND for in-OS updates,
backups and nanddump. For mtd3 rescue writes, prefer U-Boot `nand write`; Linux `nandwrite`
produced a one-byte first-byte shift on this setup. See RECOVERY.md.

## Test after rebuilding DTB/kernel

```
cat /proc/mtd
nanddump --omitoob -f /tmp/mtd1.bin /dev/mtd1
cmp -n <uImage-size> /root/uImage-6.12.117-wdnas-final /tmp/mtd1.bin
```

Verify partitions before any write. Keep `nand-backup/` and the stock mtd1/uRamdisk.

## NAND capacity

256 MiB total (`H27U2G8F2CTR`, 2 Gbit). Full Debian rootfs does not fit. See HARDWARE.md for
the practical kernel-on-NAND + USB-rootfs layout and larger-chip caveats.

## Using the unused NAND space safely

The stock Gen1 layout already uses the whole 256 MiB; there is no hidden “full capacity”:

| mtd | size | stock use | Debian today |
|---|---|---|---|
| mtd0 | 5 MiB | U-Boot | **do not touch** |
| mtd1 | 5 MiB | WD kernel | our 6.12 kernel |
| mtd2 | 5 MiB | WD uRamdisk | free (too small for embedded rescue kernel) |
| mtd3 | ~185 MiB | stock image.cfs (squashfs) | **rescue kernel in first 9.2 MiB (auto-reboot timeout)** (erase window 16 MiB); rest free (stock backup kept) |
| mtd4 | 15 MiB | rescue firmware | leave (stock rescue) |
| mtd5 | 20 MiB | config/MAC | leave |
| mtd6 | 10 MiB | reserve | leave |

Safe options, in order of risk:

1. **mtd2 (5 MiB)**, tiny raw initramfs (serial/network/diagnostics). U-Boot on this unit
   treated a separate initrd as an old ext2 ramdisk, so the reliable path is embedding the
   initramfs in a rescue kernel (used here).
2. **mtd3 (~185 MiB)**, **implemented**: embedded rescue kernel at offset 0, size
   `0x93175a` after a `nand erase 0xf00000 0x1000000` (erase window must cover the whole
   image or the tail is written over non-erased pages and readback fails `Bad Data CRC`).
   Only bad block on this chip: `0xff00000` (last block, outside our region).
   The rest of mtd3 remains free for data/rescue artifacts.
3. **mtd4–mtd6**, leave alone unless you fully understand stock rescue/config/MAC usage.
4. **Larger NAND** (512 MiB/1 GiB TSOP-48), hardware rework; not needed for rescue; full
   Debian still awkward. Not recommended.

Do **not** repartition mtd0–mtd2: U-Boot offsets are hardcoded (`0x500000` kernel, `0xa00000`
ramdisk) and the wrong change bricks the boot path. “More usable space” comes from using
mtd3 + mtd2 for rescue/data, not from resizing the boot partitions.

Reverse engineering is not the blocker: the partition map and chips are known; the Linux
NAND issue is the DTS node (`nand-controller@d0000` + child `nand@0`). REA is useful for
binaries, not needed for this layout.
