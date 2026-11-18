# Rescue initramfs, build notes

Status: **built, mtd3-flashed and boot-tested (2026-11-17)**: `uImage-rescue-tools` (9,639,770 B,
sha256 `ee2c141b04d927fa5d0e4ba748f4b8f459158cafee119c82dc33619d25694059`). Design:
`docs/RESCUE.md`; backchannel: `docs/BACKCHANNEL.md`; NAND layout: `docs/NAND.md`.

## What it does

`init` (BusyBox sh):
1. mounts proc/sys/dev, starts `mdev`;
2. DHCP on `eth0`, falls back to `192.168.1.22/24` + gateway `192.168.1.1`;
3. runs `/rescue/diagnose.sh` (kernel/cmdline, mtd, block devices, USB, network,
   RAID read-only, SMART, temps/fan, recent errors);
4. writes `/run/wd/backchannel/status.json` + `events.log`;
5. serves read-only backchannel at `:8098` (`/status.json`, `/log`);
6. starts Dropbear (key-only) if present;
7. prints the ASCII MOTD and gives a shell.

Diagnostics never mount RAID members, never format, never write NAND. Writes require explicit
commands.

## Tool bundle (target)

Static BusyBox + optional static/musl builds of:

- `dropbear` (SSH, key-only)
- `mtd-utils` (`flash_erase`, `nandwrite`, `nanddump`, `mtd_debug`)
- `e2fsprogs` (`e2fsck`, `dumpe2fs`, `resize2fs`, read-only checks first)
- `mdadm` (read-only detail; never bare `--scan`)
- `smartmontools` (`smartctl -n standby`)
- `iproute2`/BusyBox `ip`, `curl`/`wget`, `jq` if size allows
- host keys, authorized key for root, `/etc/motd`, `/etc/issue`

If the bundle does not fit mtd2 (~5 MiB compressed): keep a tiny serial/network rescue in mtd2
and put the full toolset on USB/TFTP or in mtd3.

## Build (armhf)

Two-step build (both steps verified working):

1. **Stage the tools on the NAS** (exports binaries + `ldd` closure, chroot-validated):
   ```sh
   scp rescue/stage-tools.sh root@<nas>:/tmp/
   ssh root@<nas> 'OUTPUT=/tmp/wd-tools.tar.gz sh /tmp/stage-tools.sh'
   scp root@<nas>:/tmp/wd-tools.tar.gz .   # ~3.1 MB
   ```
2. **Build the initramfs on the hypervisor**, then embed it in the kernel:
   ```sh
   BUSYBOX=/tmp/wd-rescue-inputs/busybox DROPBEAR=/tmp/wd-rescue-inputs/dropbear \
   ROOT=/tmp/wd-rescue-root OUT=/tmp/uRamdisk-rescue-tools \
   TOOLS_TAR=wd-tools.tar.gz AUTHORIZED_KEYS=<public-key-file> \
   sh rescue/build-initramfs.sh
   NAND_BUILTIN=1 ROOT=/tmp/wd-rescue-root OUT=uImage-rescue-tools \
   sh rescue/build-rescue-kernel.sh
   ```

Env: `TOOLS_TAR` (tool bundle tar.gz), `AUTHORIZED_KEYS` (client **public** key, installed
0600). Dropbear host keys are generated at boot (`dropbear -R -s`), no private key is
embedded. The tool test lives in `rescue/tool-test.sh` (read-only smoke test).

## Test before NAND

1. Copy `uRamdisk-rescue` and a kernel to TFTP root.
2. U-Boot: `tftp 0xa00000 uImage; tftp 0xf00000 uRamdisk-rescue; bootm 0xa00000 0xf00000`.
3. Verify serial MOTD, DHCP/static, SSH key login, `/proc/mtd`, `/status.json`,
   `mdadm --detail /dev/md0` (read-only), `smartctl -n standby`.
4. Only then back up mtd2 and write it. Keep stock `uRamdisk` in `nand-backup/`.

## NAND appliance (implemented, verified 2026-11-17)

The appliance is a **kernel + embedded initramfs stored in NAND** and read **only by
U-Boot** (which avoids the U-Boot<->Linux NAND ECC/read-path problems on this board).

- Image: `uImage-wd-appinst` (kernel 6.12.117-wdnas with NAND+squashfs built in,
  busybox + mtd-utils/e2fsprogs/mdadm/smartmontools/dropbear, `/dev/console`, appliance
  init). Size ~9.65 MB (`0x934d02`), flashed at **0x1840000** (84 MiB `appliance`
  partition, mtd4).
- Boot it from U-Boot: **`run wdnandos`** (saved env:
  `nand read 0xa00000 0x1840000 0xa00000; setenv bootargs console=ttyS0,115200 panic=10; bootm 0xa00000`).
- Runtime: read-only initramfs root, tmpfs `/etc,/var,/run,/tmp` seeded from
  `/etc.defaults`; DHCP->static network; **key-only Dropbear on :22** (use
  `~/.ssh/wd_key`) and read-only HTTP backchannel on **:8098** (`status.json`,
  `events.log`). `reboot` returns to the normal USB Debian.
- Build: `build-appliance-initramfs.sh` (runs `build-appliance.sh` first).
- `bootcmd` is unchanged: normal boot is the mtd1 kernel + USB root; the appliance is a
  manual fallback until a boot fallback chain is chosen.

### Script status
- `build-appliance.sh` - builds the appliance rootfs + squashfs (squashfs currently
  unused by the appliance; kept for the UBI path).
- `build-appliance-initramfs.sh` - **the one that builds the shipped appliance image**.
- `appliance-init` - the appliance PID 1.
- `build-appliance-boot.sh` + `appliance-bootstrap-init` - **superseded** (two-stage
  bootstrap, abandoned once NAND was built into the kernel).
- `write-appliance-from-linux.sh` - **reference only**: on this board Linux BCH
  `nandwrite` aborts with EINVAL partway, so images must be written by U-Boot.
- `wd-image-tool.py` - Ed25519 sign/verify/wrap for our own images (PAT-inspired).

