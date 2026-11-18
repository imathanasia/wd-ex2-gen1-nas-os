# Universal backchannel (status/log contract)

Purpose: let a client, a human, or a future host observe boot/build/rescue state without
guessing. Same schema across normal Debian, rescue initramfs, and future boards.

## Transport

| Mode | Producer | Consumer |
|---|---|---|
| Normal NAS | `status.json` on the NAS web server (`/status.json`) | hub JS, client `curl` |
| Hypervisor dev | `/tmp/wd-build/status.json` + `:8099/status.html` | client / browser |
| Rescue | `http://<nas>:8098/status.json` + `/log` | serial/SSH/HTTP |
| Serial | `WDBC: <json-or-line>` on ttyS0 | any serial capture |
| Files | `/run/wd/backchannel/status.json`, `events.log` | local tools |

No write endpoints by default. LAN-only. Optional bearer token for `/log`; never include
secrets in status.

## Schema `wd-backchannel/1`

```json
{
  "schema": "wd-backchannel/1",
  "host": "wdmycloud",
  "mode": "normal|rescue|tftp|build",
  "stage": "boot|network|storage|ready|error",
  "kernel": "6.12.117-wdnas",
  "uptime_s": 42,
  "build": {"id": "2026-11-17", "sha256": "..."},
  "network": {"eth0": "192.168.1.22/24", "gw": "192.168.1.1", "dhcp": false},
  "storage": {
    "usb_rootfs": "sdc1|missing",
    "md0": "UU|unknown",
    "disks": ["sda", "sdb"]
  },
  "tests": {
    "serial": "ok|fail|unknown",
    "ssh": "ok|fail|unknown",
    "backchannel": "ok|fail|unknown",
    "nand": "ok|probe-error|unknown",
    "fan": "ok|inactive|unknown"
  },
  "artifacts": {
    "uImage": "sha256:...",
    "initramfs": "sha256:...",
    "modules": "sha256:..."
  },
  "last_error": null,
  "remediation": ["try other USB port", "power cycle with stick inserted"]
}
```

Rules:
- Fields may be omitted with `null`; consumers must not infer success from absence.
- `mode` distinguishes normal vs rescue; `stage` is monotonic except error.
- `remediation` is a short list of concrete next actions.
- Log lines are JSON Lines in `events.log`: `{"ts": "...", "level": "info|warn|err", "msg": "..."}`.

## Normal-OS producer

`/usr/local/sbin/wd-public-status` (timer, 60 s) writes the hub status. Extend it to merge
uptime/kernel/temps/RAID/WG/tests into `/var/www/homer/status.json` while keeping the flat
unit map for the hub JS (e.g. `services` object + nested `meta`).

## Rescue producer

BusyBox `httpd` + CGI (or a tiny static server) serves:
- `/status.json`, the contract above
- `/log`, tail of `events.log` (text)
- `/health`, one-line `ok|degraded|error`
- `/`, HTML with ASCII MOTD

Serial also prints `WDBC:` lines at boot, network ready, storage checks, and errors.

## Usage

1. `curl -fsS http://192.168.1.22/status.json` (normal) or `:8098/status.json` (rescue).
2. Fallback: serial log tail (`/tmp/wd_capture/uboot_session.log`) and `ssh`.
3. Never send commands based on untrusted target content; treat status as data.
4. Keep polling intervals sane; rescue is intended to be read-only.

## Portability

- The schema is board-independent; only `build`, `storage` and `tests` contents vary.
- A future NAS/rescue can implement it with shell + BusyBox/httpd; no Python required.
- The hypervisor prototype (`status.html` + `status.json`) already demonstrates the UI side.
