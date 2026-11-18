# WD My Cloud EX2 (Gen1) hardware notes

Model family: **WDBVKW…** = My Cloud EX2 **Gen1** (not Ultra). WDBVBZ… = EX2 Ultra.
Board: **RD-88F6710_Alpha_KingsCanyon** (U-Boot banner). SoC: Marvell MV6710 / 88F6710 Armada 370,
single Cortex-A9 @ 1.2 GHz, 512 MiB DDR3.

## Components (observed / sourced)

| Part | Detail |
|---|---|
| SoC | Marvell Armada 370 MV6710, 1.2 GHz, single core |
| RAM | 2× Nanya NT5CB256M8FN-DI DDR3, 512 MiB total |
| NAND | SK hynix H27U2G8F2CTR (256 MiB usable; 128 KiB erase, 2 KiB page, 64 B OOB) |
| Ethernet PHY | Marvell Alaska: board photos say **88E1518**; gisab DTS says 88E1318; Linux PHY driver reports 88E1510-compatible. Verify against PCB marking before quoting. |
| USB 3.0 | NEC/Renesas D720202 (xHCI, PCIe) |
| SATA | Integrated in Armada 370 (AHCI), 2 ports |
| RTC | Armada RTC (no battery on some units) |
| Fan | **Sunon MC35101V1-000U-G99** |
| Power LED | WD Apollo3G `a3g_led` MMIO driver (not GPIO) |
| MCU | Weltrend on UART1 (`mpp60/61`); exact Gen1 part not confirmed |
| Front panel | 12-pin LED header; HDD LEDs are GPIOs |

## Fan, Sunon MC35101V1-000U-G99

- 35 × 35 × 10 mm, 12 VDC, 0.72 W (max 0.83 W), **9500 rpm ±25%**, **7.0 CFM**,
  0.18 inH2O, **28 dBA**, 3-wire (12 V / GND / tach), Vapo bearing, 60,000 h @ 40 °C.
- Linux `gpio-fan` uses **4 GPIOs**: `mpp6`, `mpp8`, `mpp16`, `mpp32`
  (`&gpio0 6/8/16`, `&gpio1 0`). gisab DT speed-map: `0/1500/1700/1800/2100` (nominal).
  No tach input is wired to Linux; `/sys/class/hwmon/hwmon1/fan1_input` reports the nominal
  speed of the selected level (e.g. 1700 at state 2).
- Stock WD userspace `fan_control -f 0..6` advertises **0 / 4000 / 5000 / 6000 / 7000 /
  8000 / 9000 rpm**. The stock controller uses the Weltrend MCU/MIPC path, not the 4-GPIO
  `gpio-fan` path; the DT speed-map is therefore **not the full range**.
- Stock thermal policy (`/etc/fan_temperature.txt` on older firmware):
  `TEMPERATURE_STOP=39`, `TEMPERATURE_LOW=45`, `TEMPERATURE_HIGH=49`; newer firmware moved
  thresholds into its settings DB. WD's published table shows **0 rpm at idle drive temps
  around 50 °C**, fan starts around 56–57 °C. So idle fan-off is normal stock behaviour.
- Our `wd-fan.service` policy: min level 1; level 2 at >55 °C; 3 at >64 °C; 4 at >72 °C
  (state 2 @ ~60 °C → 1700 nominal). Aggressive policy is under review because the
  enclosure is small and 3.5" drives add heat.
- Practical cooling options: keep a minimum level (airflow/noise trade-off); replace with a
  higher-static 40 mm fan if the 35 mm mount allows; external 80/120 mm fan for heavy loads;
  ensure vents/dust are clear. A 35 mm 7 CFM fan is marginal for two 3.5" drives.

## GPIO / pin map (from gisab Gen1 DTS)

| Function | Pins |
|---|---|
| HDD LEDs | mpp52 (hdd2-red), mpp53 (hdd1-red), mpp55 (hdd2-blue), mpp57 (hdd1-blue) |
| Fan | mpp6, mpp8, mpp16, mpp32 |
| USB3 power | mpp13 (`enable-active-high`) |
| SATA-1 power | mpp54 (pinctrl reports “unsupported function gpio”; regulator may be always-on) |
| SATA-2 power | mpp56 |
| UART1 (Weltrend MCU) | mpp60 TX, mpp61 RX |
| Reset button | mpp64 |
| UART0 console | mpp? (ttyS0, 115200) |

## NAND layout (stock Gen1)

| mtd | offset/size | contents |
|---|---|---|
| mtd0 | 0x000000 / 5 MiB | U-Boot |
| mtd1 | 0x500000 / 5 MiB | kernel uImage (stock Linux 3.2.40; now our 6.12.117-wdnas) |
| mtd2 | 0xA00000 / 5 MiB | uRamdisk |
| mtd3 | 0x0F00000 / ~201 MiB | squashfs rootfs (offset 2048 in the image) |
| mtd4 |, | rescue firmware |
| mtd5/mtd6 |, | UBI/config/reserve |

## NAND capacity / rootfs options

- Chip is **H27U2G8F2CTR = 2 Gbit = 256 MiB**, TSOP-48, 3.3 V, 2 KiB page / 128 KiB block,
  large-block SLC. Total mtd space is 256 MiB; mtd3 rootfs area is ~201 MiB.
- Larger TSOP-48 SLC parts exist (e.g. H27U4G8F2D 4 Gbit/512 MiB, H27U8G8G5D 8 Gbit/1 GiB)
  but are **not plug-and-play**: same package does not guarantee the same page/block/ECC
  geometry, and U-Boot, bad-block tables, partitions and ECC config must match. Board rework
  and a full reflash are required; risk is high.
- A full Debian 12 rootfs is >1 GiB, so **it cannot fit 256 MiB NAND**; even 1 GiB is tight
  and wears the NAND. Practical layouts:
  1. **NAND = kernel + DTB (+ optional initramfs/rescue)**; rootfs on USB (current), USB SSD/DOM,
     SATA or NFS.
  2. USB rootfs (current 128 GB JetFlash), fastest to iterate; cold-boot if USB3 enumeration stalls.
  3. SATA/other disk rootfs only if data layout allows; do not disturb the RAID1 members.
- Linux NAND access is **fixed** (`nand-controller@d0000` + child `nand@0`); normal Debian
  shows mtd0–mtd6 and `/dev/mtd1`. Earlier failure was `marvell-nfc … invalid resource`
  (`nand@d0000`);
  fix the DTS NAND node (`reg`, clocks) for Linux-side flashing. U-Boot flashing works today.

## Power LED / LEDs

- Power LED is driven by WD's **Apollo3G** MMIO LED driver (`drivers/leds/leds-apollo3g.c`
  in WD GPL / MyBookLive patches). Bits: red `0x10`, green `0x20`, blue `0x40`.
- The MyBookLive patch uses base `0x4e0000000ULL`; the Gen1 EX2 base is **not yet verified**.
  Do not write random MMIO. HDD LEDs use `leds-gpio` and already work.

## MCU / fan control truth

- Stock `fan_control` is an **armel** binary (needs `/lib/ld-linux.so.3`); it uses
  `libmipc`/`libtemperature` and writes MIPC CPU registers `0x18100/0x18140`
  (bits `0x40/0x800/0x1000/0x10000/0x100/0x1` for levels).
- Raw `/dev/ttyS1` probes at 19200 binary (Ultra frames) and 9600/19200 ASCII got **no reply**.
  The Gen1 MCU path is not directly usable without the WD MIPC stack.
- `gpio-fan` is the practical Linux path; `alarm-gpios` must not overlap a fan GPIO
  (that caused `-EBUSY`; removed).

## Sources

- gisab/WDMC-Ex2 DTS + kernel config (Gen1).
- OpenWrt PR #17779 / #26000 (Ultra/Mirror Gen2 WT6703F; useful comparison only).
- WD Community teardown/fan threads; eTeknix/Legit Reviews board photos.
- Sunon MC35101V1-000U-G99 datasheet.
- MyBookLive `03_enable_leds.patch` (a3g driver).
