# Rescue Tool Bundle Implementation Plan

**Goal:** Add mtd-utils, e2fsprogs, mdadm, and smartmontools to the NAND-booted rescue initramfs without changing its read-only behavior or key-only SSH.

**Architecture:** A staging script on the NAS (armhf Debian) exports the recovery binaries plus their resolved shared-library closure as a tar.gz; the rescue initramfs build unpacks that bundle and an authorized public key into the embedded root; the existing embedded-rescue-kernel pipeline rebuilds, TFTP/RAM-tests, then replaces mtd3 via U-Boot (Linux mtd is page-shifted on this box and must not write boot artifacts).

**Tech Stack:** POSIX sh, tar/cpio, armhf Debian 12 binaries, kernel 6.12.117-wdnas with `CONFIG_INITRAMFS_SOURCE`, U-Boot TFTP/`nand` commands.

**Spec:** `docs/plans/rescue-tool-bundle-design.md`

## Global Constraints

- Verification commands are the record.
- Never write NAND from Linux (`nandwrite`/`dd` page-shift observed). mtd3 writes only via U-Boot, one command at a time, waiting for `Marvell>>` between commands (`/tmp/wd_send.sh` on the hypervisor).
- TFTP/RAM boot test MUST pass before any mtd3 erase/write.
- Rescue stays read-only: no RAID assembly, no member mounts, SMART with `-n standby`, no automated fsck repair, no HTTP write endpoints.
- No private SSH keys in tracked files; Dropbear server host keys stay runtime-generated (`dropbear -R`).
- Inventory: hypervisor `builder@192.168.1.4` (key `/root/projects/serve/hypervisor-key`, NOPASSWD sudo); NAS `root@192.168.1.22` via hypervisor jump with `/home/builder/.ssh/wd_key`. Kernel tree `/home/builder/wd-build/linux-6.12.117`; TFTP root `/tmp/wd_boot/boot/`; rescue scaffolding `/root/projects/wdbvkw0060jch-20/rescue/`.
- mtd3 rescue slot: `nand erase 0xf00000 0x700000`; boot `nand read 0xa00000 0xf00000 <size>; bootm 0xa00000`. Current image size `0x6be58a` (may change — always use the fresh `mkimage` size).

## Review Focus

- Library closure completeness (loader, `libstdc++`/`libgcc_s` for smartctl, `libudev` for mdadm): each bundled binary must execute under `chroot` of the staged tree — test in Task 1.
- BusyBox applet shadowing: `busybox --install` must not replace any bundled tool (e2fsck/mdadm/smartctl/mtd tools are not BusyBox applets; assert after build in Task 2).
- authorized_keys mode/ownership (600, under root-only `/root/.ssh`) — assert in Task 2, runtime-verified by key-only SSH in Task 4.
- U-Boot discipline: every command awaited via `wd_send.sh`; erase only after `Bytes transferred` observed — enforced in Tasks 4–5.
- Post-flash return to normal: fan/WG/RAID/hub must be re-verified in Task 5 before docs claim success.

---

### Task 1: `rescue/stage-tools.sh` — export tool + library bundle from the NAS

**Files:**
- Create: `rescue/stage-tools.sh`
- Produces (on hypervisor): `/home/builder/wd-build/wd-tools.tar.gz` + sha256

**Interfaces:**
- Consumes: NAS binaries `/usr/sbin/{flash_erase,nandwrite,nanddump,mtd_debug,mdadm,smartctl}`, `/sbin/{e2fsck,resize2fs,dumpe2fs,tune2fs}`; `ldd` for closure.
- Produces: tar.gz with layout `./sbin/ ./usr/sbin/ ./lib/` (loader + all resolved libs) and `sbin/fsck.ext4 -> e2fsck` symlink; env `OUTPUT` (default `/tmp/wd-tools.tar.gz`); exits nonzero naming any missing binary or unresolved lib.

- [ ] **Step 1: Write `rescue/stage-tools.sh`** — copies binaries with `cp --parents`, computes the `ldd` closure (rejecting non-absolute/unresolved entries), ensures the ELF loader, creates the `fsck.ext4` symlink, then validates every binary by running `chroot "$STAGE" "$b" --version` (fails on "not found"/"No such file"/empty output), then writes the tar.gz and prints sha256+size.
- [ ] **Step 2: Run it on the NAS** — push script via SSH, `OUTPUT=/tmp/wd-tools.tar.gz sh /tmp/stage-tools.sh`; Expected: per-tool version lines, then `sha256sum` printed.
- [ ] **Step 3: Verify the bundle** — `tar -tzf` lists all 10 binaries + loader + `libstdc++`, `libudev`; scp to hypervisor; re-verify sha256 matches. Expected: identical digest.

### Task 2: extend `rescue/build-initramfs.sh` with `TOOLS_TAR` + `AUTHORIZED_KEYS`

**Files:**
- Modify: `rescue/build-initramfs.sh`
- Modify: `rescue/README.md` (new env vars, bundle layout)

**Interfaces:**
- Consumes: Task 1 tar.gz; hypervisor public key `/home/builder/.ssh/wd_key.pub`.
- Produces: rescue root with BusyBox + tools + `root/.ssh/authorized_keys` (600); env `TOOLS_TAR`, `AUTHORIZED_KEYS` (both required for this build; missing → clear error).

- [ ] **Step 1: Edit build script** — after BusyBox install: require `AUTHORIZED_KEYS`, install it (600) into `$ROOT/root/.ssh/authorized_keys`; if `TOOLS_TAR` set, unpack into `$ROOT`; error if either input is missing.
- [ ] **Step 2: Build and inspect root** — run with `ROOT=/tmp/wd-rescue-root TOOLS_TAR=/home/builder/wd-build/wd-tools.tar.gz AUTHORIZED_KEYS=/home/builder/.ssh/wd_key.pub`; Expected: all 10 tool paths exist, BusyBox still at `/bin/busybox`, no bundled tool path differs from the binary list, authorized_keys mode 600, `init` intact.
- [ ] **Step 3: Sanity-run closure in the assembled root** — for two representative binaries (`smartctl`, `mdadm`), `LD_TRACE_LOADED_OBJECTS=1` against the root's loader shows no "not found". Expected: clean.

### Task 3: rebuild embedded rescue kernel with tools

**Files:**
- Consumes: `rescue/build-rescue-kernel.sh` (unchanged), Task 2 root
- Produces: `/home/builder/wd-build/uImage-rescue-tools`

- [ ] **Step 1: Build** — `NAND_BUILTIN=1 ROOT=/tmp/wd-rescue-root OUT=/home/builder/wd-build/uImage-rescue-tools sh rescue/build-rescue-kernel.sh` on the hypervisor; Expected: build log clean, `mkimage` succeeds.
- [ ] **Step 2: Record identity** — `mkimage -l` on the output; capture exact file size in hex + sha256 for Tasks 4–5 and docs.

### Task 4: TFTP/RAM boot + tool smoke test (no NAND write)

**Files:**
- Create: `rescue/tool-test.sh` — read-only smoke test run over rescue SSH

**Interfaces:**
- Consumes: `uImage-rescue-tools` at TFTP name `uImage-rescue-tools`; `/tmp/wd_send.sh`; authorized key.
- Produces: PASS evidence for every tool before flashing.

- [ ] **Step 1: Copy image to TFTP root** and record `ls -l`.
- [ ] **Step 2: RAM boot** — reboot to U-Boot with spam discipline, then one-command-at-a-time: `setenv serverip/ipaddr`, `tftp 0xa00000 uImage-rescue-tools` (wait for `Bytes transferred`), `bootm 0xa00000`. **No erase/write.**
- [ ] **Step 3: Smoke test over SSH** — `rescue/tool-test.sh` asserts: every tool prints a version line; `mdadm --detail /dev/md0` shows State without assembling; `smartctl -n standby -H /dev/sda /dev/sdb` PASSED; `/proc/mtd` lists mtd0–6; `:8098/status.json` returns 200. Expected: all PASS, no repair/assembly/write side effects.
- [ ] **Step 4: Return to normal** — `reboot` from rescue (U-Boot env untouched); verify normal NAS: fan active, wg0, md0, `http://192.168.1.22/` 200.

### Task 5: flash mtd3 via U-Boot + final boot verification

- [ ] **Step 1: Flash** — at clean `Marvell>>`: `tftp 0xa00000 uImage-rescue-tools` (verify byte count), `nand erase 0xf00000 0x700000`, `nand write 0xa00000 0xf00000 <size-hex>`, `nand read`, `bootm`. Each command via `wd_send.sh`.
- [ ] **Step 2: Boot test from mtd3** — rescue SSH + full `tool-test.sh` PASS; backchannel 200.
- [ ] **Step 3: Return to normal and re-verify** — reboot; fan/WG/RAID/hub 200; then save artifact to `/srv/nas/backups/rescue/uImage-rescue-tools` (digest match).

### Task 6: docs + status

- [ ] **Step 1: Update docs** — `RESCUE.md` (toolset verified + image size/sha), `NAND.md` (mtd3 slot facts), `RECOVERY.md` (rescue boot command with new size), `NOTES.md` (new dated section incl. e2fsck-shipped decision), `rescue/README.md`.
- [ ] **Step 2: Update `status.json`** rescue block on the backchannel.
