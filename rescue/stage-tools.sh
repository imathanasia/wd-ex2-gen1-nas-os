#!/bin/sh
# Stage rescue tools + shared-library closure into a tarball.
# Run ON the NAS (armhf Debian): read-only against the source system.
# OUTPUT=/tmp/wd-tools.tar.gz sh stage-tools.sh
set -eu

OUTPUT=${OUTPUT:-/tmp/wd-tools.tar.gz}
STAGE=$(mktemp -d /tmp/wd-tools.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

BINARIES="
/usr/sbin/flash_erase
/usr/sbin/nandwrite
/usr/sbin/nanddump
/usr/sbin/mtd_debug
/sbin/e2fsck
/sbin/resize2fs
/sbin/dumpe2fs
/sbin/tune2fs
/usr/sbin/mdadm
/usr/sbin/smartctl
"

echo "== binaries =="
for b in $BINARIES; do
  [ -f "$b" ] || { echo "missing: $b" >&2; exit 1; }
  cp --parents "$b" "$STAGE/"
  echo "ok: $b"
done

# conventional fsck frontend
ln -s e2fsck "$STAGE/sbin/fsck.ext4"

echo "== library closure =="
LIBS=$(for b in $BINARIES; do ldd "$b" 2>/dev/null; done \
  | awk '$2=="=>"{print $3} $1 ~ /^\//{print $1}' | sort -u)
[ -n "$LIBS" ] || { echo "no libraries resolved" >&2; exit 1; }
for l in $LIBS; do
  case "$l" in
    /*) cp --parents "$l" "$STAGE/"; echo "lib: $l" ;;
    *) echo "unresolved library entry: $l" >&2; exit 1 ;;
  esac
done
LOADER=/lib/ld-linux-armhf.so.3
[ -f "$LOADER" ] || { echo "missing loader: $LOADER" >&2; exit 1; }
cp --parents "$LOADER" "$STAGE/"

echo "== chroot validation =="
for b in $BINARIES; do
  out=$(chroot "$STAGE" "$b" --version 2>&1 | head -1)
  case "$out" in
    *"not found"*|*"No such file"*|*"error while loading"*)
      echo "chroot failed: $b: $out" >&2; exit 1 ;;
  esac
  [ -n "$out" ] || { echo "chroot no output: $b" >&2; exit 1; }
  echo "runs: $b -> $out"
done

echo "== archive =="
tar -C "$STAGE" -czf "$OUTPUT" ./sbin ./usr ./lib
chmod 644 "$OUTPUT" 2>/dev/null || true
sha256sum "$OUTPUT"
ls -l "$OUTPUT"
