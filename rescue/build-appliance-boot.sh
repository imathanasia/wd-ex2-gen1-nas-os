#!/bin/sh
# Build the appliance BOOT image: kernel + tiny initramfs (waits for mtdblock4,
# mounts squashfs, switch_root) + appliance DTB appended.
# Output: /home/builder/wd-build/uImage-wd-app2  -> flash at 0xdd00000 (stock
# "rescue-firmware" region; stock mtd4.bin is backed up).
set -eu
LINUX=/home/builder/wd-build/linux-6.12.117
BOOTSRC=/home/builder/wd-build/appliance-boot
INIT=/home/builder/wd-build/appliance-bootstrap-init
DTB="$LINUX/arch/arm/boot/dts/marvell/armada-370-wd-my-cloud-ex2-appliance.dtb"
OUT=/home/builder/wd-build/uImage-wd-app2
CROSS=arm-linux-gnueabihf-
BUSYBOX=/tmp/wd-rescue-inputs/busybox

[ -x "$BUSYBOX" ] || { echo "busybox missing: $BUSYBOX"; exit 1; }
[ -f "$INIT" ]    || { echo "init missing: $INIT"; exit 1; }
[ -f "$DTB" ]     || { echo "dtb missing: $DTB"; exit 1; }

rm -rf "$BOOTSRC"; mkdir -p "$BOOTSRC/bin"
cp "$BUSYBOX" "$BOOTSRC/bin/busybox"; chmod 755 "$BOOTSRC/bin/busybox"
# CRITICAL: an embedded initramfs OVERWRITES the kernel's built-in /dev/console.
# Without these device nodes the kernel cannot open an initial console, init gets
# no stdio (silent), and a shell exits immediately -> "Attempted to kill init".
mkdir -p "$BOOTSRC/dev"
mknod -m 622 "$BOOTSRC/dev/console" c 5 1 2>/dev/null || sudo -n mknod -m 622 "$BOOTSRC/dev/console" c 5 1
mknod -m 666 "$BOOTSRC/dev/null" c 1 3 2>/dev/null || sudo -n mknod -m 666 "$BOOTSRC/dev/null" c 1 3
mknod -m 620 "$BOOTSRC/dev/ttyS0" c 4 64 2>/dev/null || sudo -n mknod -m 620 "$BOOTSRC/dev/ttyS0" c 4 64
cp "$INIT" "$BOOTSRC/init"; chmod 755 "$BOOTSRC/init"

cd "$LINUX"; cp .config .config.appbak
# NAND is a module in the normal config (loaded from the USB rootfs). The
# appliance has no modules, so build the NAND stack in for mtdblock4 to exist.
scripts/config --enable MTD --enable MTD_RAW_NAND --enable MTD_NAND --enable MTD_NAND_MARVELL
scripts/config --enable MTD_BLOCK
scripts/config --set-str INITRAMFS_SOURCE "$BOOTSRC"
scripts/config --enable INITRAMFS_COMPRESSION_GZIP 2>/dev/null || true
make ARCH=arm CROSS_COMPILE=$CROSS olddefconfig >/tmp/app-olddef.log 2>&1
grep -E '^CONFIG_INITRAMFS_SOURCE' .config
make ARCH=arm CROSS_COMPILE=$CROSS -j4 zImage >/tmp/app-kernel-build.log 2>&1
cat arch/arm/boot/zImage "$DTB" > /tmp/zImage-app2
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 \
  -n Kernel-6.12.117-wdnas-app2 -d /tmp/zImage-app2 "$OUT"
cp .config.appbak .config
echo "built: $OUT ($(stat -c%s "$OUT") bytes, hex $(printf '0x%x' "$(stat -c%s "$OUT")"))"
sha256sum "$OUT"
