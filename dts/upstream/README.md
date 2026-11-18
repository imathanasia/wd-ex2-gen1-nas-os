# DTS variants

| File | Purpose |
|---|---|
| `armada-370-wd-my-cloud-ex2.dts` | **the upstream submission** (stock partition layout; used by the patch + cover letter) |
| `armada-370-wd-my-cloud-ex2-appliance.dts` | local variant: splits `image.cfs` into a 9.25 MiB rescue slot + 84 MiB `appliance` partition (mtd4) |
| `...-appliance-hamming.dts` | experiment: `nand-ecc-strength = <1>` (Hamming layout test) |
| `...-appliance-noecc.dts` | experiment: `nand-ecc-mode = "none"` (ECI disabled) |
| `...-appliance-noecc-nobbt.dts` | experiment: ECC none + no on-flash BBT (in-RAM BBT only) |
| `0001-...patch`, `0000-cover-letter.md` | packaged upstream patch + cover letter |

Notes from the NAND experiments (see `docs/NAND-FULL-SPACE.md`): Linux MTD reads are
shifted +1 byte and Linux BCH writes abort with EINVAL on this board; ECC-none writes work
but are not bitflip-protected. Only the upstream file and the `-appliance` variant are
supported; the hamming/noecc files are experimental evidence.
