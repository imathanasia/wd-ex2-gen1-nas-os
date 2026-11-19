# Hypervisor cleanup / preserved artifacts (2026-11-18)

Host: `agent@192.168.1.4` (`pve`), access via `ssh -i /root/projects/serve/agent-pve-key -p 22 -o IdentitiesOnly=yes agent@192.168.1.4` (see `/root/projects/HYPERVISOR-ACCESS.md`).

## WD NAND backup (preserved)

- Copied from hypervisor `/home/agent/wd-nand-backup/` to this repo: `hypervisor-backups/wd-nand-backup-2026-11-18.tar.gz`
- Size: 111M
- SHA256: `3f90814b552357e222432ffb950ae07952ec6e1d6feefcb0060fcd6b999cc39d`
- Verify: `sha256sum hypervisor-backups/wd-nand-backup-2026-11-18.tar.gz`
- Original directory remains on hypervisor at `/home/agent/wd-nand-backup/`.

## wd-build trimmed to rebuild inputs/docs

`/home/agent/wd-build` reduced from ~3.8G to ~388K. Removed extracted kernel trees/tarballs, built images/modules/appliance artifacts, and disposable logs/outputs (`linux-6.12.117*`, `linux-5.10.109*`, `uImage-*`, `zImage_*`, `modules-*`, `appliance.squashfs`, `output`, `dropbear-src`, `appliance-boot`, etc.).

Retained rebuild inputs/scripts/docs:
- `appliance-bootstrap-init`, `appliance-init`
- `bootlog_debian_tux.txt`
- `build-appliance-boot.sh`, `build-appliance-initramfs.sh`, `build-appliance.sh`
- `config-6.12.117`
- `initramfs-init`
- `install-cgi`
- `kernel.config-5.10.109-armada370`
- `rescue/build-initramfs.sh`, `rescue/build-rescue-kernel.sh`, `rescue/diagnose.sh`, `rescue/init`, `rescue/motd.sh`, `rescue/motd.txt`
- `setup-index.html`

Rebuild outputs/artifacts are not stored on hypervisor after cleanup; regenerate from these inputs and project docs/scripts as needed.

## Other hypervisor state (2026-11-18)

- `/home/agent/ac68u/`: scratch firmware `.trx` files removed (~267M); kept `femctrl6-readback.sh`.
- `/var/tmp`: removed stale `.guestfs-0` and `vzdumptmp83452_104`; remaining entries are system-managed.
- `/home/agent/iqnap/`: kept (active development, ~14G).
- `/home/agent/syno-pat/`: reduced to `tools/` and `mining/` (~2.3M). Removed `pats/`, `venv/`, and extracted `work/` (ds213j/ds218j trees; required `sudo -n` for root-owned files). PAT inputs/rebuilt outputs/venv can be regenerated from retained tools and project notes.
- Kept: `/home/agent/wd-gpl/`, `/home/agent/wd-mockups/`, `/home/agent/wd-nand-backup/`.

## Resume

- Before state-changing actions, re-verify host identity and `sudo -n` as in `HYPERVISOR-ACCESS.md`.
- For WD rescue/appliance/kernel rebuild work, use retained `wd-build` inputs plus this project's `rescue/`, `dts/`, `docs/`, and `scripts/`; do not assume removed hypervisor build artifacts exist.
- NAND backup archive in this repo is the preserved local copy; original remains on hypervisor.
