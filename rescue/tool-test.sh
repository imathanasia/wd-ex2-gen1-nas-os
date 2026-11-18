#!/bin/sh
# Rescue tool smoke test — READ-ONLY. Run over SSH in rescue (or normal) OS.
# Never assembles RAID, never wakes standby disks, never writes flash.
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

echo "== rescue tool smoke test =="

for t in flash_erase nandwrite nanddump e2fsck resize2fs dumpe2fs tune2fs mdadm smartctl; do
  if command -v "$t" >/dev/null 2>&1; then
    case "$t" in
      e2fsck|tune2fs) out=$("$t" -V 2>&1 | head -1) ;;
      mtd_debug) out=$(mtd_debug 2>&1 | head -1) ;;
      *) out=$("$t" --version 2>&1 | head -1) ;;
    esac
    [ -n "$out" ] && pass "$t [$out]" || fail "$t no version output"
  else
    fail "$t not found"
  fi
done
out=$(mtd_debug 2>&1 | head -1); [ -n "$out" ] && pass "mtd_debug [$out]" || fail mtd_debug "no usage output"

MD=$(mdadm --detail /dev/md0 2>/dev/null | grep -E "State|Active Devices" | head -2 | tr '\n' ' ')
if [ -b /dev/md0 ]; then
  [ -n "$MD" ] && pass "mdadm detail: $MD" || fail "mdadm --detail /dev/md0 empty"
else
  pass "mdadm: /dev/md0 not assembled (expected read-only rescue)"
fi

for d in /dev/sda /dev/sdb; do
  if [ -b "$d" ]; then
    H=$(smartctl -n standby -H "$d" 2>/dev/null | grep -E "PASSED|FAILED" | head -1)
    [ -n "$H" ] && pass "smart $d: $H" || fail "smart $d no health line"
  else
    echo "SKIP: $d not present"
  fi
done

MTDN=$(grep -c "^mtd" /proc/mtd 2>/dev/null || echo 0)
[ "${MTDN:-0}" -ge 7 ] && pass "/proc/mtd $MTDN partitions" || fail "/proc/mtd only $MTDN partitions"

if wget -q -O- http://127.0.0.1:8098/status.json 2>/dev/null | grep -q wd-backchannel; then
  pass "backchannel :8098/status.json"
else
  echo "WARN: backchannel :8098 not answering (normal OS does not run it)"
fi

echo "== result: $([ "$FAIL" = 0 ] && echo ALL_PASS || echo HAS_FAILURES) =="
exit "$FAIL"
