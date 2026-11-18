# Web UI

The live dashboard runs at `/` on the NAS. It reads `/status.json` and
`/diag.json` every 15 seconds.

The top bar holds the name, current host and a search box. The left rail shows
the core service count, CPU temperature, fan speed, memory, load, storage use,
RAID state and disk temperatures. Every value in the rail comes from the live
status files.

The main area has six action tiles: Files, Photos, Music, AdGuard, Toggles and
Help. A tile dims when its service is stopped. The service list below the tiles
has switches for non-critical units. Critical units show a "managed" badge and
cannot be stopped from the web page.

The library strip points to local folders and their apps. It also dims when the
related service is stopped.

The page uses `location.hostname` for every link, so an IP change does not break
the dashboard. The layout collapses to one column on a phone, with the status
rail first.

The recovery installer is a separate page served from the NAND rescue image.
See `rescue/setup/index.html` in this repo and `INSTALL-START-HERE.md` for the
steps to reach it.
