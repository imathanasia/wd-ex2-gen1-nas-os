#!/bin/sh
# systemd system-shutdown hook: ask the MCU to cut power on a real poweroff.
# Runs after filesystems are unmounted; only stdio/basic binaries needed.
case "$1" in
  poweroff)
    [ -x /usr/local/sbin/wd-mcu ] && /usr/local/sbin/wd-mcu poweroff >/dev/null 2>&1
    sleep 1
    ;;
esac
exit 0
