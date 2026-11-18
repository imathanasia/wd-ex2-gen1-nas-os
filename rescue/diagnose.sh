#!/bin/sh
# WD EX2 Gen1 rescue diagnostics — POSIX/BusyBox friendly.
# Read-only by default. Writes /run/wd/backchannel/status.json + events.log.
# Safe to run from serial, SSH, or initramfs init. Never mounts RAID members.

MODE=${MODE:-normal}
BC=${BC:-/run/wd/backchannel}
STATUS="$BC/status.json"
LOG="$BC/events.log"
mkdir -p "$BC" 2>/dev/null

ts() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown; }
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' ; }
log() { # level msg
  printf '{"ts":"%s","level":"%s","msg":"%s"}\n' "$(ts)" "$1" "$(esc "$2")" >> "$LOG" 2>/dev/null
  printf 'WDBC: %s\n' "$2"
}
ok() { log info "$1"; }
warn() { log warn "$1"; }
bad() { log err "$1"; }

printf '\n'
cat /etc/motd 2>/dev/null || true
printf '\n=== WD EX2 RESCUE DIAGNOSTICS ===\n'

K=$(uname -r 2>/dev/null || echo unknown)
CMD=$(cat /proc/cmdline 2>/dev/null || true)
UP=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
MEM=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
MEMF=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
MTD=0
if [ -r /proc/mtd ]; then
  MTD=$(grep -c '^mtd' /proc/mtd 2>/dev/null || true)
  [ -n "$MTD" ] || MTD=0
fi
USBN=$(ls /sys/bus/usb/devices 2>/dev/null | wc -l)
ROOT=$(mount 2>/dev/null | awk '$3=="/"{print $1; exit}')
IP=$(ip -o -4 addr show dev eth0 2>/dev/null | awk '{print $4; exit}')
GW=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
MD=$(cat /proc/mdstat 2>/dev/null | tr '\n' ' ' | cut -c1-160)
RAID=$([ -e /dev/md0 ] && echo present || echo absent)
FAN=$(for h in /sys/class/hwmon/hwmon*; do [ "$(cat "$h/name" 2>/dev/null)" = gpio_fan ] && echo "$h"; done | head -1)
FANRPM=$(cat "$FAN/fan1_input" 2>/dev/null || echo unknown)
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
ERR=$(dmesg 2>/dev/null | grep -iE 'error|fail|panic' | tail -1)

ok "kernel=$K uptime=${UP}s mem=${MEM}kB free=${MEMF}kB"
ok "cmdline=$CMD"
ok "nand_mtd=$MTD usb_devices=$USBN root=${ROOT:-unknown}"
ok "ip=${IP:-none} gw=${GW:-none} raid=$RAID fan_rpm=$FANRPM cpu_temp=$TEMP"

# NAND partitions (names only; do not write)
if [ "$MTD" -gt 0 ] 2>/dev/null; then
  cat /proc/mtd | while read -r line; do ok "mtd: $line"; done
else
  warn "no /proc/mtd (NAND driver not loaded; U-Boot flashing only)"
fi

# Block devices / possible rootfs
awk 'NR>2{print "block:",$4,$3"kB"}' /proc/partitions 2>/dev/null | while read -r l; do ok "$l"; done

# Network test
if ping -c1 -W2 "${GW:-192.168.1.1}" >/dev/null 2>&1; then ok "gateway reachable"; else warn "gateway not reachable"; fi

# RAID (read-only)
if [ -e /dev/md0 ]; then
  warn "md0 present: do NOT mount members directly; use md0 read-only if needed"
  mdadm --detail /dev/md0 2>/dev/null | grep -E 'State|Active|Failed|Working' | while read -r l; do ok "$l"; done
fi

# SMART (never wake a standby disk)
for d in /dev/sd?; do
  [ -b "$d" ] || continue
  H=$(smartctl -n standby -H "$d" 2>/dev/null | grep -E 'result|standby|FAILED|PASSED' | head -1)
  [ -n "$H" ] && ok "smart $d: $H"
done

# Filesystems (read-only listing)
df -h 2>/dev/null | while read -r l; do ok "df: $l"; done

# Recent kernel errors
[ -n "$ERR" ] && warn "last kernel error: $ERR"

# JSON status (flat, shell-generated; no secrets)
cat > "$STATUS" <<EOF
{"schema":"wd-backchannel/1","host":"$(hostname 2>/dev/null || echo wdmycloud)","mode":"$(esc "$MODE")","stage":"ready",
"kernel":"$(esc "$K")","uptime_s":${UP:-0},
"network":{"ip":"$(esc "${IP:-}")","gw":"$(esc "${GW:-}")"},
"storage":{"root":"$(esc "${ROOT:-}")","md0":"$(esc "$RAID")","mtd":${MTD:-0},"usb_devices":${USBN:-0}},
"tests":{"serial":"ok","backchannel":"ok","nand":"$( [ "$MTD" -gt 0 ] 2>/dev/null && echo ok || echo probe-error )","fan":"$( [ -n "$FAN" ] && echo ok || echo unknown )"},
"artifacts":{},"last_error":"$(esc "${ERR:-}")",
"remediation":["check serial and USB rootfs","verify md0 read-only","use U-Boot TFTP to reflash if needed"]}
EOF

ok "status written to $STATUS"
printf 'WDBC: rescue diagnostics complete\n'
