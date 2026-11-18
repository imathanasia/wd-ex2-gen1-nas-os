# Project notes

Build: EX2-Gen1-v1.

## Hardware

- WD My Cloud EX2 Gen1, board RD-88F6710 "KingsCanyon".
- Marvell Armada 370, 512 MB RAM, no NEON.
- Two SATA bays, USB 3.0 root, Gigabit ethernet, dead RTC battery.
- Serial console on JP2, 115200 8N1, 3.3V TTL only.

## Boot and storage

- Stock U-Boot stays in NAND mtd0.
- Custom Linux 6.12 kernel in mtd1, with a fallback copy at `0xdd00000`.
- Debian 12 armhf root on a USB stick by PARTUUID.
- RAID1 md0 on the SATA bays, mounted at `/srv/nas`.
- NAND mtd6 holds stock config data and is left alone.
- Rescue image in mtd3 with SSH, diagnostics and HTTP backchannel `:8098`.

## Software

Core services:

- Samba with wsdd, NFS, FileBrowser, AdGuard Home.
- WireGuard and Tailscale for remote access.
- lighttpd serves the dashboard and the rescue setup page.

On-demand apps:

- Copyparty, Syncthing, Navidrome, Transmission, minidlna, Glances, CUPS.
- They stay off at boot to protect RAM.

## Daily use

- Dashboard at `/` reads `/status.json` and `/diag.json`.
- Service switches call `wd-control` on port 8081.
- Critical units are shown as managed and cannot be stopped from the web page.
- MOTD shows live system state on the console.

## Install

See `docs/INSTALL-START-HERE.md`.

- First install needs serial access once to load the kernel.
- Setup image asks for DHCP, then falls back to `192.168.1.22/24`.
- Demo defaults are listed in the install guide and must be changed.

## Recovery

See `docs/RECOVERY.md` and `docs/RESCUE.md`.

- Shell access is available on the serial console.
- Rescue SSH uses keys, not a password.
- Diagnostics are read-only by default.

## Known limits

- The RTC battery is dead, so the clock is set from an HTTP `Date:` header.
- The WD web updater cannot install this unsigned kernel.
- Full NAND operations should be tested in RAM first.
- The NAS web server blocks `/screenshots/`, so captures are embedded in the README.
