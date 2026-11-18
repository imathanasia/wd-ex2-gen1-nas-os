# Weltrend MCU (WT6703), protocol & implementation

Source: vendor/community notes from the **WD My Cloud Mirror Gen1** archive
(`fox-exe.ru/WDMyCloud/WDMyCloud-Mirror/Developing/notes.txt.sh`). The EX2 Gen1 is the
**same hardware** (the archive's own Info.txt: *"Look for WDMC-Mirror (Gen1), it's the same
devices"*).

## Transport
`/dev/ttyS1` (UART1, mpp60/61), **115200 8N1**, raw. Frames: `0xFA <len> <cmd> <args...> 0xFB`.

## Commands (vendor frames)
| Action | Frame |
|---|---|
| Device ready / OS load done | `FA 03 01 00 00 00 FB` |
| **Shutdown (cut power)** | `FA 03 03 01 01 14 FB` |
| Power LED on | `FA 03 06 01 00 01 FB` |
| Power LED off | `FA 03 06 00 00 01 FB` |
| Power LED blink | `FA 03 06 02 00 01 FB` |
| WoL enable | `FA 03 0A 01 00 00 FB` |
| WoL disable | `FA 03 0A 00 00 00 FB` |
| WoL status | `FA 03 0A 02 00 00 FB` |
| Read RTC date/time | `FA 01 08 01 01 00 FB` |
| Read board temperature | `FA 03 08 00 00 00 FB` |

**Reads do not return data on this unit** (tested 9600/19200/115200), RX from the MCU
appears not wired/usable, so every command is used fire-and-forget.

## GPIO map (from the same notes), matches our DTS
`6` fan max · `8` fan min · `16` fan power · `32` fan med · `13` USB power ·
`50` HDD2 state · `51` HDD1 state · `52` HDD2 red · `53` HDD1 red · `54` HDD2 power ·
`55` HDD2 blue · `56` HDD1 power · `57` HDD1 blue · `64` reset button (active-low)

Our DTS fan GPIOs (mpp6/8/16/32), LEDs (mpp57/55/53/52), USB power (mpp13), reset (mpp64)
are all correct.

## Implemented on the device
- `rescue/wd-mcu` -> `/usr/local/sbin/wd-mcu` (`ready|poweroff|led on|off|blink|wol on|off|status|temp|rtc`).
- `wd-mcu.service` (oneshot, enabled): `ready` + `led on` + `wol on` at boot.
- `/usr/lib/systemd/system-shutdown/wd-mcu-shutdown`: on **poweroff** sends the shutdown
  frame so the MCU cuts power (clean power-off instead of a halted-but-powered unit).

## How to verify
- **Power LED**: `wd-mcu led blink` / `led off` / `led on` (visual).
- **Clean poweroff**: `poweroff` should now physically turn the unit off (MCU cuts power);
  power it back on with the front button.
- **WoL**: `wd-mcu wol on` at boot; test with `wakeonlan <mac>` from another host once the
  unit is powered off (MCU keeps the NIC alive).

## Firmware container format (reference)
The stock update file is a header + [uImage | uRamdisk | image.cfs | default.tar.gz |
uP.bin] with CRC32s per part, codename string ("KingsCa…") and a version string; see the
vendor notes for the exact 128-byte header layout (not used by our pipeline).
