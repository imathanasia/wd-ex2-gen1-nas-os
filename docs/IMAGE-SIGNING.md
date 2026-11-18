# Image signing & verification

Status: **tool implemented and tested** (2026-11-17). Optional integration into the
rescue/kernel build pipeline.

## Why

The image wrapper binds every firmware payload with three mechanisms:

1. a **magic sentinel** so a reader instantly rejects the wrong artifact type,
2. an **Ed25519 detached signature** over the payload digest, and
3. a **SHA-256 digest** carried in the header and re-checked before use.

We already rely on U-Boot read-back checksums (`Checksum OK`) when flashing mtd1/mtd3.
That catches transport corruption but says nothing about *which* bytes were written or
*who* produced them. Signing our images closes the "did I flash the right, untampered
build?" gap and gives us a machine-checkable provenance record in the repo.

## Tool

`rescue/wd-image-tool.py` (pure Python, uses `cryptography`; OpenSSL 3 also present).

| command | purpose |
|---------|---------|
| `keygen -o DIR` | generate `wd-image.key` (PKCS#8 PEM, 0600) + `wd-image.pub` |
| `sign IMAGE [-k KEY] [-o SIG]` | detached Ed25519 signature (`IMAGE.sig`) |
| `verify IMAGE [-s SIG] [-p PUB]` | verify; exit 1 on mismatch |
| `wrap IMAGE -o OUT [-k KEY]` | prepend signed self-describing header |
| `info WRAPPED` | print header + recomputed digest compare |
| `unwrap WRAPPED -o OUT [-p PUB]` | verify then strip header |

### Wrapped format (`WDNASIMG`)

```
offset size  field
0      8     magic  "WDNASIMG"
8      2     version (u16 LE)      = 1
10     2     flags   (u16 LE)      = 0
12     8     payload_len (u64 LE)
20     32    sha256(payload) raw
52     2     siglen (u16 LE)       = 64
54     64    Ed25519 signature over canonical(magic,ver,flags,payload_len,sha256)
118    ...   payload bytes
```

Signature message = `HDR_PREFIX.pack(MAGIC, ver, flags, payload_len, sha256)`, i.e.
the signed 52-byte prefix. The payload itself is bound through its SHA-256, so the
signature covers content + all header fields, so the signature commits to both the header fields and the payload.

## Test evidence (2026-11-17, /tmp/opencode/wt-test)

```
keygen -> keys/wd-image.key + wd-image.pub   (pubkey sha256 f20dc323…)
sign   4096-byte fake uImage                 -> fake-uImage.sig
verify (valid)                               -> OK
verify (1 byte flipped)                       -> FAIL, exit=1
wrap  -> 118-byte header + 4096 payload
info  -> digest MATCH
unwrap (+pubkey) -> payload byte-identical (cmp)
unwrap (tampered payload) -> "payload digest mismatch; refusing", exit=1
```

All seven checks pass.

## Recommended workflow

1. `wd-image-tool.py keygen -o keys/` once; commit **only** `wd-image.pub`
   (keep `wd-image.key` offline / in the build host, add to `.gitignore`).
2. After building `uImage-rescue-*` / `uImage-6.12.117-wdnas*`:
   `wd-image-tool.py wrap <uImage> -o <uImage>.wrapped -k keys/wd-image.key`
3. Before any `nand write`, run `wd-image-tool.py info <file>` and confirm
   `digest: MATCH`; optionally `verify` the detached `.sig`.
4. Optional: embed `wd-image.pub` in the rescue initramfs and have `init` refuse to
   `bootm`/flash a wrapped image whose signature fails (future).

## Key handling

The keypair is generated locally and only the public key is committed. No external
key material is involved.

## Related

- `docs/RESCUE.md`, where wrapped images slot into the recovery path.
- `docs/NAND.md`, U-Boot read-back checksum step that this complements.
