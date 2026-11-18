#!/bin/sh
# Write the appliance squashfs into /dev/mtd4 ("appliance", 84 MiB) FROM LINUX so
# that the data uses the Linux marvell_nand ECC/OOB layout (U-Boot-written pages
# are unreadable by Linux on this stock 2011.12 U-Boot).
# Run on the NAS (normal Debian boot). Verify with nanddump + sha256 afterwards.
set -eu
IMG=${1:-/tmp/appliance.squashfs}
DEV=${DEV:-/dev/mtd4}
SIZE=$(stat -c%s "$IMG")

echo "image: $IMG ($SIZE bytes)"
echo "target: $DEV"
[ -c "$DEV" ] || { echo "ERROR: $DEV missing"; exit 1; }
command -v flash_erase >/dev/null || { echo "ERROR: flash_erase (mtd-utils) missing"; exit 1; }
command -v nandwrite  >/dev/null || { echo "ERROR: nandwrite (mtd-utils) missing"; exit 1; }

echo "== erase =="
flash_erase "$DEV" 0 0
echo "== nandwrite =="
nandwrite -p "$DEV" "$IMG"
echo "== verify (nanddump | sha256) =="
WANT=$(sha256sum "$IMG" | cut -d' ' -f1)
GOT=$(nanddump -l "$SIZE" "$DEV" 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "want: $WANT"
echo "got:  $GOT"
if [ "$WANT" = "$GOT" ]; then echo "VERIFY: OK"; else echo "VERIFY: MISMATCH"; exit 2; fi
