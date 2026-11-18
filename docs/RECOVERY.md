# Recovery / flashing the WD EX2 Gen1

## Serial

- CH341 USB-serial on the hypervisor; port can re-enumerate (`ttyUSB0`/`ttyUSB1`).
- 115200 8N1, 3.3 V, cross TX/RX/GND; console server:
  `/tmp/wd_console_srv.py <log> /tmp/wd_cmd.fifo`
- Send a line by writing to `/tmp/wd_cmd.fifo`; the server appends `\r`.
- Hold U-Boot: root spam `/tmp/wd_spam2.sh` (must run as root; `/dev/ttyUSB*` is
  `root:dialout`). Wait for `Marvell>>`, then kill the spam PID from `/tmp/wd_spam.pid`.
- SysRq reboot: serial **BREAK** then `b` (Python `TIOCSBRK`, 0.3 s, `TIOCCBRK`, then `b`).
  Do **not** run the `1` spam during the break, `1` changes loglevel instead of rebooting.

## U-Boot TFTP flash (safe, NAND only)

TFTP root on hypervisor: `/tmp/wd_boot/boot`; LAN server binds `192.168.1.4:69`.
Images:
- `uImage-wd-final`, final 6.12.117 with fan fix + WireGuard + NAND + Renesas; file size
  **0x47476d** (4,671,341 bytes)
- `uImage-wd-new`, earlier fan/WG image, size **0x4732ad**
- `uImage-wd`, 5.10 gisab fallback

At `Marvell>>` (one command at a time, wait for output):

```
setenv serverip 192.168.1.4
setenv ipaddr 192.168.1.22
printenv serverip          # must show 192.168.1.4
tftp 0xa00000 uImage-wd-final
# wait for: Bytes transferred = 4671341 (47476d hex)
nand erase 0x500000 0x500000
nand write 0xa00000 0x500000 0x47476d
nand read 0xa00000 0x500000 0x500000
bootm 0xa00000
```

**Never send erase/write while TFTP is still running.** U-Boot only reads queued serial input
after the current command completes, which can create a dangerous backlog.

## USB rootfs notes

- Rootfs is on a 128 GB Transcend JetFlash USB3 (`LABEL=rootfs`,
  `PARTUUID=b07640b0-01`), currently `sdc1`.
- After several warm reboots the stick sometimes does not enumerate on xHCI; a **cold power
  cycle** (unplug 10 s, replug) with the stick inserted fixes it. U-Boot EHCI cannot see the
  USB3 stick; use Linux for that.
- If it still fails: try the other USB3 port, reseat, or verify the stick on another PC.
- Rootfs failure symptom: kernel logs stop at `Waiting for root device
  PARTUUID=b07640b0-01...`; RAID/SATA disks are still visible.

## Linux-side NAND (FIXED)

The DTS was fixed (`nand-controller@d0000` + child `nand@0`) and flashed. Normal Debian now
shows `/proc/mtd` with mtd0–mtd6 and `/dev/mtd1`; NAND is available for in-OS updates/backups.
For the **mtd3 rescue** write, prefer U-Boot `nand write`, Linux mtd reads/writes are
page-shifted on this setup. Rescue U-Boot sequence (one command at a time, wait for each
`Marvell>>`):
```
nand erase 0xf00000 0x1000000
nand write 0xa00000 0xf00000 0x931be2
nand read 0xa00000 0xf00000 0x931be2
bootm 0xa00000
```
The readback must print `Verifying Checksum ... OK`; `Bad Data CRC` means a stale/partial
erase window, re-erase 16 MiB and rewrite. Rescue SSH is key-only Dropbear without scp:
pipe files via `ssh root@... "cat > /path" < file`.

## Fallbacks

- Stock NAND images: `nand-backup/mtd0.bin` … `mtd6.bin` + `mtd3.img`.
- U-Boot environment is unchanged; a failed NAND boot still leaves U-Boot reachable on serial.
- Do not mount a RAID member directly; only `/dev/md0`.
