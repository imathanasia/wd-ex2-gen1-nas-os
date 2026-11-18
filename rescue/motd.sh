#!/bin/sh
# Colored rescue MOTD (POSIX/BusyBox printf). ASCII penguin with an open belly hatch.
C1='\033[1;36m'   # cyan frame
C2='\033[1;32m'   # green
C3='\033[1;33m'   # yellow
C4='\033[1;35m'   # magenta
C5='\033[1;31m'   # red
C0='\033[0m'
printf '%b' "$C1"
cat <<'ART'
        .-""""""-.
       /  .--.    \
      |  /    \    |
      | |  ()  |   |
      |  \____/    |
       \  ____    /
        '-.__.-'
      .-""""""-.
     /  .--.     \
    |  /    \     |
    | | (^ω^) |   |
    |  \____/     |
     \  ____     /
      '-.__.-'
ART
printf '%b' "$C0$C2"
printf '   W D   E X 2   //   R E S C U E   M O D E\n'
printf '%b' "$C0$C3"
printf '   ImAthanasia  ·  KingsCanyon  ·  serial 115200 8N1\n'
printf '%b' "$C0$C4"
printf '   ssh root@192.168.1.22  ·  backchannel :8098\n'
printf '%b' "$C0$C1"
printf '   ----------------------------------------------------\n'
printf '%b' "$C0$C5"
printf '   (^ω^)   no data was touched  ·  read-only by default\n'
printf '%b' "$C0$C2"
printf '   checks: status  disks  smart  raid  net  log\n'
printf '%b' "$C0$C3"
printf '   kernel: %s\n' "$(uname -r 2>/dev/null || echo unknown)"
printf '   eth0:   %s\n' "$(ip -o -4 addr show dev eth0 2>/dev/null | awk '{print $4; exit}' || echo unknown)"
printf '%b' "$C0$C1"
printf '   ----------------------------------------------------\n'
printf '%b' "$C0"
