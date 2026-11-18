# Cover letter template, WD My Cloud EX2 (Gen1) board DTS

> **Before sending:** replace the `From:`/`Signed-off-by:` identity with your real
> name + email (`git send-email --smtp-server ...` uses your `git config user.*`).
> The current patch uses the placeholder `imathanasia@users.noreply.github.com`.

```
Subject: [PATCH 0/1] ARM: dts: armada-370: Add WD My Cloud EX2 (Gen1)

Hello,

This series adds a board file for the Western Digital My Cloud EX2 (Gen1)
NAS (board RD-88F6710 "KingsCanyon", Marvell Armada 370 / 88F6710), which
has no mainline board file today.

Enabled by the board: both SATA ports, USB2 and USB3 hosts, gpio HDD
status LEDs, the 4-GPIO chassis fan (gpio-fan, 1500/1700/1800/2100 rpm
speed map), the rear reset button, mvneta ethernet with the Marvell
88E1510 phy (rgmii-id), fixed regulators gating USB and SATA disk power,
and the NAND controller with the stock fixed partition layout.

The NAND node sets "marvell,nand-keep-config": the stock bootloader programs
controller timings that mainline does not reproduce on this board (reprogramming
them corrupts reads and aborts writes), matching the Armada 370 Seagate boards.

The file is derived from the Armada 370 DB reference design with the
community GPL description for the WD My Cloud Mirror Gen1 as the
hardware reference, adjusted to the EX2: NAND moved to the mainline
nand-controller + nand@0 binding (the legacy "nand@d0000" node has no
reg resource), and the gpio-fan node does not claim an alarm gpio
overlapping one of the fan speed GPIOs.

Tested on hardware (6.12.117): boots unattended from NAND with USB root,
RAID1 md0 assembles, LEDs/fan/ethernet/NAND operational; the DTB passes
dtbs_check with the same legacy-dtsi warning set as the existing
armada-370 boards (57, identical to armada-370-netgear-rn102.dtb), with
zero board-specific findings.

Tool-assistance disclosure: portions of this patch were prepared with
the help of a tool; I reviewed, built, and tested the
result on hardware and take full responsibility for its content.
Signed-off-by is mine (human).

Patch: [PATCH 1/1] attached.

Best regards,
ImAthanasia
https://github.com/ImAthanasia
```

To:      linux-arm-kernel@lists.infradead.org
Cc:      devicetree@vger.kernel.org
Cc:      gregory.clement@bootlin.com
Cc:      robh@kernel.org, krzk+dt@kernel.org, conor+dt@kernel.org
