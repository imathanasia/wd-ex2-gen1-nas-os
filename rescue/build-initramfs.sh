#!/usr/bin/env bash
# Build a minimal armhf rescue initramfs for WD My Cloud EX2 Gen1.
# STATUS: scaffold — review paths/tools before trusting. Test via TFTP first.
set -eu

OUT=${OUT:-./uRamdisk-rescue}
ROOT=${ROOT:-./build/root}
BUSYBOX=${BUSYBOX:-/usr/bin/busybox}          # armhf static busybox
DROPBEAR=${DROPBEAR:-/usr/sbin/dropbear}      # armhf (static or with libs)
FILES=${FILES:-.}

TOOLS_TAR=${TOOLS_TAR:-}
AUTHORIZED_KEYS=${AUTHORIZED_KEYS:-}

[ -n "$AUTHORIZED_KEYS" ] || { echo "AUTHORIZED_KEYS not set (path to a public key)" >&2; exit 1; }
[ -f "$AUTHORIZED_KEYS" ] || { echo "AUTHORIZED_KEYS missing: $AUTHORIZED_KEYS" >&2; exit 1; }
if [ -n "$TOOLS_TAR" ]; then
  [ -f "$TOOLS_TAR" ] || { echo "TOOLS_TAR missing: $TOOLS_TAR" >&2; exit 1; }
fi

echo "[1/5] clean root"
rm -rf "$ROOT" "$OUT"
for d in bin sbin etc proc sys dev tmp run root rescue www usr/bin usr/sbin; do
  mkdir -p "$ROOT/$d"
done

echo "[2/5] userspace"
install -m 0755 "$BUSYBOX" "$ROOT/bin/busybox"
DROPBEARKEY=${DROPBEARKEY:-$(dirname "$DROPBEAR")/dropbearkey}
[ -f "$DROPBEAR" ] || { echo "dropbear missing: $DROPBEAR" >&2; exit 1; }
install -m 0755 "$DROPBEAR" "$ROOT/usr/sbin/dropbear"
if [ -f "$DROPBEARKEY" ]; then
  install -m 0755 "$DROPBEARKEY" "$ROOT/usr/sbin/dropbearkey"
fi
for a in sh mount umount fsck dd nc wget vi top ps dmesg ip ifconfig udhcpc mdev tar gzip cat ls cp mv rm mkdir ln sleep date; do
  [ "$a" = busybox ] && continue
  ln -sf /bin/busybox "$ROOT/bin/$a"
done
# Optional tools: mtd-utils, e2fsprogs, smartmontools, mdadm, curl, dropbear.
# Copy them with their shared libraries, or use static builds.

echo "[3/5] tools + keys"
if [ -n "$TOOLS_TAR" ]; then
  tar -C "$ROOT" -xzf "$TOOLS_TAR"
  for t in sbin/e2fsck usr/sbin/mdadm usr/sbin/smartctl usr/sbin/nandwrite; do
    [ -f "$ROOT/$t" ] || { echo "tool bundle incomplete: $t" >&2; exit 1; }
  done
  echo "tools staged from $TOOLS_TAR"
fi
install -d -m 0700 "$ROOT/root/.ssh"
install -m 0600 "$AUTHORIZED_KEYS" "$ROOT/root/.ssh/authorized_keys"

echo "[3b/5] config + motd"
cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat > "$ROOT/etc/group" <<'EOF'
root:x:0:
EOF
echo wdmycloud > "$ROOT/etc/hostname"
install -m 0644 "$FILES/motd.txt" "$ROOT/etc/motd" 2>/dev/null || true
install -m 0755 "$FILES/motd.sh" "$ROOT/etc/motd.sh" 2>/dev/null || true
cat > "$ROOT/etc/issue" <<'EOF'
WD EX2 Gen1 RESCUE - ImAthanasia - serial 115200 8N1
EOF
install -d "$ROOT/rescue" "$ROOT/www" "$ROOT/etc/dropbear"
install -m 0755 ./diagnose.sh "$ROOT/rescue/diagnose.sh"

echo "[4/5] init"
install -m 0755 ./init "$ROOT/init"

echo "[5/5] cpio.gz"
( cd "$ROOT" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$OUT"
ls -lh "$OUT"
echo "Next: TFTP-test with kernel: tftp 0xa00000 uImage; tftp 0xf00000 uRamdisk-rescue; bootm 0xa00000 0xf00000"
