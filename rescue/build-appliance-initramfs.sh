#!/bin/sh
# Build the appliance as an INITRAMFS image (kernel + embedded cpio), to be read
# from NAND by U-Boot only. This avoids the U-Boot<->Linux NAND ECC mismatch on
# this board (Linux ecc_strength=16/step=2048 vs U-Boot's layout => EIO).
# Output: /home/builder/wd-build/uImage-wd-appinst ; flash at 0x1840000 (appliance, 84 MiB).
set -eu
LINUX=/home/builder/wd-build/linux-6.12.117
ROOT=/tmp/appliance-root
DTB="$LINUX/arch/arm/boot/dts/marvell/armada-370-wd-my-cloud-ex2-appliance.dtb"
OUT=/home/builder/wd-build/uImage-wd-appinst
CROSS=arm-linux-gnueabihf-

# Rebuild the appliance rootfs (also produces /tmp/appliance-root) and the squashfs
/home/builder/wd-build/build-appliance.sh >/dev/null
[ -d "$ROOT" ] || { echo "missing $ROOT"; exit 1; }

# Embedded initramfs must ship /dev/console or the kernel has no initial console
mkdir -p "$ROOT/dev"
for spec in "console c 5 1 622" "null c 1 3 666" "ttyS0 c 4 64 620"; do
  set -- $spec; name=$1; typ=$2; maj=$3; min=$4; mode=$5
  [ -e "$ROOT/dev/$name" ] || sudo -n mknod -m "$mode" "$ROOT/dev/$name" "$typ" "$maj" "$min" 2>/dev/null || mknod -m "$mode" "$ROOT/dev/$name" "$typ" "$maj" "$min" 2>/dev/null || true
done
ls -l "$ROOT/dev" || true

cd "$LINUX"; cp .config .config.inst.bak
scripts/config --enable MTD --enable MTD_RAW_NAND --enable MTD_NAND --enable MTD_NAND_MARVELL --enable MTD_BLOCK
scripts/config --set-str INITRAMFS_SOURCE "$ROOT"
# Files in $ROOT are owned by the build user; tell gen_init_cpio to map them to root
scripts/config --set-val INITRAMFS_ROOT_UID "$(id -u)" 2>/dev/null || scripts/config --set-str INITRAMFS_ROOT_UID "$(id -u)"
scripts/config --set-val INITRAMFS_ROOT_GID "$(id -g)" 2>/dev/null || scripts/config --set-str INITRAMFS_ROOT_GID "$(id -g)"
scripts/config --enable INITRAMFS_COMPRESSION_GZIP 2>/dev/null || true
make ARCH=arm CROSS_COMPILE=$CROSS olddefconfig >/tmp/inst-olddef.log 2>&1
grep -E '^CONFIG_INITRAMFS_SOURCE=' .config
make ARCH=arm CROSS_COMPILE=$CROSS -j4 zImage >/tmp/inst-kernel.log 2>&1
cat arch/arm/boot/zImage "$DTB" > /tmp/zImage-inst
mkimage -A arm -O linux -T kernel -C none -a 0x8000 -e 0x8000 \
  -n Kernel-6.12.117-wdnas-appinst -d /tmp/zImage-inst "$OUT" >/dev/null
cp .config.inst.bak .config
SZ=$(stat -c%s "$OUT")
printf 'built: %s (%s bytes, hex 0x%x)\n' "$OUT" "$SZ" "$SZ"
sha256sum "$OUT"
