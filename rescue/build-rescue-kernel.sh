#!/bin/sh
# Build a rescue kernel with the initramfs EMBEDDED (CONFIG_INITRAMFS_SOURCE).
# This bypasses the U-Boot legacy-initrd path that our separate uRamdisk hit.
# Test via TFTP first; never flash this over the normal kernel until tested.
set -e

LINUX=${LINUX:-/home/builder/wd-build/linux-6.12.117}
ROOT=${ROOT:-/tmp/wd-rescue-root}
DTS=${DTS:-arch/arm/boot/dts/marvell/armada-370-wdmc-mirror-gen1-gs.dts}
DTB=${DTB:-arch/arm/boot/dts/marvell/armada-370-wdmc-mirror-gen1-gs.dtb}
OUT=${OUT:-/home/builder/wd-build/uImage-rescue-embedded}
NAND_BUILTIN=${NAND_BUILTIN:-0}
CROSS=${CROSS:-arm-linux-gnueabihf-}

cd "$LINUX"
[ -d "$ROOT" ] || { echo "rescue root missing: $ROOT"; exit 1; }
[ -f "$DTS" ] || { echo "DTS missing: $DTS"; exit 1; }
cp .config .config.normal

# Embed the rescue root; keep gzip if the symbol exists.
if [ "${NAND_BUILTIN:-0}" = "1" ]; then
  scripts/config --enable MTD_RAW_NAND --enable MTD_NAND_MARVELL
fi
scripts/config --set-str INITRAMFS_SOURCE "$ROOT"
scripts/config --enable INITRAMFS_COMPRESSION_GZIP 2>/dev/null || true
make ARCH=arm CROSS_COMPILE="$CROSS" olddefconfig >/tmp/rescue-olddef.log 2>&1
grep -E '^CONFIG_INITRAMFS_SOURCE' .config || true
make ARCH=arm CROSS_COMPILE="$CROSS" -j12 zImage >/tmp/rescue-kernel-build.log 2>&1
cat arch/arm/boot/zImage "$DTB" > /tmp/zImage_and_dtb-rescue
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 \
  -n Kernel-6.12.117-wdnas-rescue -d /tmp/zImage_and_dtb-rescue "$OUT"
cp .config.normal .config
echo "built: $OUT"
ls -lh "$OUT"
echo "Next: TFTP-boot $OUT with bootm (no separate ramdisk); verify rescue MOTD/diagnostics/NAND."
