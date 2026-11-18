#!/bin/bash
# Build the NAND squashfs appliance rootfs for WD My Cloud EX2 Gen1.
# Reuses the hardware-validated rescue userspace staging (/tmp/wd-rescue-root):
# busybox + mtd-utils/e2fsprogs/mdadm/smartmontools/dropbear + ldd-closure libs.
# Output: /home/builder/wd-build/appliance.squashfs (xz) ready to flash at 0x1840000.
set -eu
SRC=/tmp/wd-rescue-root
OUT=/tmp/appliance-root
INIT_SRC=/home/builder/wd-build/appliance-init
SQ=/home/builder/wd-build/appliance.squashfs

[ -d "$SRC" ] || { echo "missing $SRC (rescue staging)"; exit 1; }
[ -f "$INIT_SRC" ] || { echo "missing $INIT_SRC"; exit 1; }

rm -rf "$OUT"; cp -a "$SRC" "$OUT"

# read-only-root convention: defaults in /etc.defaults, tmpfs copies at boot
rm -rf "$OUT/etc.defaults"; mv "$OUT/etc" "$OUT/etc.defaults"
mkdir -p "$OUT/etc" "$OUT/var" "$OUT/run" "$OUT/tmp" "$OUT/mnt" "$OUT/overlay"

# real DHCP support for udhcpc (rescue staged without it)
mkdir -p "$OUT/usr/share/udhcpc"
cat > "$OUT/usr/share/udhcpc/default.script" <<'EOS'
#!/bin/sh
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"
case "$1" in
  deconfig) ip addr flush dev "$interface" 2>/dev/null ;;
  bound|renew)
    ip addr add "$ip$NETMASK" dev "$interface" 2>/dev/null
    while ip route del default 2>/dev/null; do :; done
    for r in ${router:-}; do ip route add default via "$r" dev "$interface" 2>/dev/null; done
    ;;
esac
exit 0
EOS
chmod +x "$OUT/usr/share/udhcpc/default.script"

# ensure busybox applet symlinks exist for everything the init calls by name
mkdir -p "$OUT/sbin" "$OUT/usr/sbin" "$OUT/usr/bin"
for a in sh sleep httpd hostname ping ip udhcpc ifconfig mount umount mdev date awk sed grep cat cut tr head tail uname chown chmod ln mkdir rm touch wc du ps reboot poweroff halt fdisk blkid sha256sum findmnt tee xz zcat gunzip; do
  [ -e "$OUT/bin/$a" ] || ln -sf /bin/busybox "$OUT/bin/$a"
done
for a in switch_root; do
  [ -e "$OUT/sbin/$a" ] || ln -sf /bin/busybox "$OUT/sbin/$a"
done

# setup-mode web page + installer CGI (DSM-styled landing page for the boot manager)
rm -rf "$OUT/setup"; mkdir -p "$OUT/setup/cgi-bin"
if [ -f /home/builder/wd-build/setup-index.html ]; then
  cp /home/builder/wd-build/setup-index.html "$OUT/setup/index.html"
fi
if [ -f /home/builder/wd-build/install-cgi ]; then
  cp /home/builder/wd-build/install-cgi "$OUT/setup/cgi-bin/install"; chmod 755 "$OUT/setup/cgi-bin/install"
fi
# installer tooling (mke2fs + libs) staged from the NAS
if [ -f /home/builder/wd-build/app-extras.tgz ]; then
  tar xzf /home/builder/wd-build/app-extras.tgz --strip-components=1 --no-same-owner -C "$OUT" 2>/dev/null || true
fi

# appliance init replaces the initramfs init
cp "$INIT_SRC" "$OUT/init"; chmod 755 "$OUT/init"

# sanity: key bits present
for f in bin/busybox usr/sbin/dropbear sbin/e2fsck usr/sbin/mdadm usr/sbin/smartctl rescue/diagnose.sh root/.ssh/authorized_keys usr/share/udhcpc/default.script init; do
  [ -e "$OUT/$f" ] || { echo "MISSING in rootfs: $f"; exit 1; }
done

rm -f "$SQ"
mksquashfs "$OUT" "$SQ" -comp xz -noappend -no-recovery -quiet >/dev/null 2>&1
echo "built: $SQ ($(stat -c%s "$SQ") bytes)"
# pad info: must fit the appliance partition 0x5400000 (84 MiB) and be eraseblock-aligned
SZ=$(stat -c%s "$SQ"); echo "hex size: $(printf '0x%x' "$SZ")"
