# Rescue Tool Bundle Design

## Intent

Make the existing NAND-booted EX2 Gen1 rescue environment useful for offline recovery by bundling `mtd-utils`, selected `e2fsprogs`, `mdadm`, and `smartmontools`, while preserving its serial/SSH access and read-only startup behavior.

## Goals

- The mtd3 rescue image boots without USB rootfs or network access.
- Required tools and their runtime libraries are available in the embedded initramfs.
- Startup diagnostics use `mdadm --detail` and `smartctl -n standby`; they do not assemble arrays, wake disks, mount members, or write flash.
- Root login remains public-key-only. The authorized client public key is bundled; Dropbear server host keys are generated at boot with `dropbear -R` and private host keys are not embedded in the image.
- Keep U-Boot as the mtd3 image writer because Linux mtd reads/writes were observed shifted per NAND page.

## Non-goals

- Do not change the normal Debian rootfs, U-Boot environment, NAND partition map, or normal kernel.
- Do not make the rescue auto-run filesystem repair, RAID assembly, NAND erase/write, or formatting.
- Do not expose write-capable HTTP endpoints.

## Approaches

1. **Bundle Debian armhf executables and their resolved shared-library closure** (chosen). These packages are already installed and tested on the matching Debian armhf system. Keep the static BusyBox and Dropbear setup, stage only selected recovery binaries/libraries, then embed them in the existing rescue kernel. This is the smallest implementation with the fewest ABI surprises.
2. **Statically cross-compile every utility.** More self-contained per binary, but adds cross-build maintenance and library-specific work without improving the current independent boot path.
3. **Keep the full utilities on USB/TFTP.** Smallest NAND image, but the standalone rescue loses the very tools needed when the USB/network path is unavailable.

## Design

- Add a reproducible staging step that runs on the matching armhf Debian system, copies selected package executables and all dynamically resolved dependencies into a tar archive, and leaves the source system unchanged.
- Teach `build-initramfs.sh` to validate and unpack that archive into the rescue root, retain static BusyBox applets, and install the supplied `authorized_keys` file with restrictive permissions.
- Use runtime-generated Dropbear host keys (`-R`); document that clients may see a new host fingerprint on each rescue boot.
- Include flash tools for explicit operator use, but keep diagnostics read-only and continue recommending U-Boot for rescue-image writes.
- Boot-test the rebuilt image via the existing U-Boot path before replacing mtd3. Verify every requested binary starts, dependencies resolve, authorized-key SSH succeeds, backchannel works, `mdadm --detail` is read-only, and SMART uses `-n standby`.

## Constraints

- Target: ARMv7/armhf, Debian 12 libraries, kernel `6.12.117-wdnas`.
- The current rescue kernel image is approximately 6.8 MiB; mtd3 is approximately 205 MiB. The 5 MiB mtd2 limit does not constrain this embedded mtd3 rescue image.
- Do not put private SSH host keys or client keys in tracked source. The current build artifact's `authorized_keys` is a public key and must remain outside the repository unless the owner explicitly supplies a distributable key.
- Never run a destructive utility during automated smoke tests.

## Acceptance

- Staging and initramfs build fail clearly for missing tools, unresolved libraries, or missing authorized-key input.
- The built initramfs contains the requested tools and loader/library closure, with ownership and modes suitable for root rescue.
- TFTP/RAM boot tests pass before the operator-approved U-Boot mtd3 replacement; after boot, serial, SSH, diagnostics, and HTTP backchannel work.
- Existing normal Debian boot, fan, WireGuard, RAID, and web UI remain operational after returning from rescue.
