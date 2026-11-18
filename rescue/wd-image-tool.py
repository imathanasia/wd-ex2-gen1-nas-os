#!/usr/bin/env python3
"""wd-image-tool: sign/verify/wrap WD-NAS images (magic header + Ed25519 + SHA-256).

Uses a self-describing container with a magic sentinel,
Ed25519 detached signature, digest binding) but using OUR own keys and a
simple self-describing header so rescue/kernel images cannot be silently
tampered with or mistaken for another artifact.

Subcommands:
  keygen  [-o DIR]                 generate Ed25519 keypair (openssl-compatible)
  sign    IMAGE [-k KEY] [-o SIG]  write detached Ed25519 signature
  verify  IMAGE [-s SIG] [-p PUB]  verify detached signature
  wrap    IMAGE -o OUT [-k KEY]    prepend signed header -> self-verifying image
  info    WRAPPED                  print header fields
  unwrap  WRAPPED -o OUT           strip header (verifies first)
"""
import argparse
import hashlib
import os
import struct
import sys

MAGIC = b"WDNASIMG"
VERSION = 1
HDR_PREFIX = struct.Struct("<8sHHQ32s")   # magic, ver, flags, payload_len, sha256
HDR = struct.Struct("<8sHHQ32sH")         # + siglen
SIG_LEN = 64

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey, Ed25519PublicKey)
    from cryptography.hazmat.primitives import serialization
    HAVE_CRYPTO = True
except Exception:
    HAVE_CRYPTO = False


def _die(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def _load_priv(path):
    with open(path, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)


def _load_pub(path):
    with open(path, "rb") as f:
        return serialization.load_pem_public_key(f.read())


def canonical_bytes(ver, flags, payload_len, digest):
    return HDR_PREFIX.pack(MAGIC, ver, flags, payload_len, digest)


def cmd_keygen(args):
    if not HAVE_CRYPTO:
        _die("python 'cryptography' package required")
    d = args.out
    os.makedirs(d, exist_ok=True)
    priv = Ed25519PrivateKey.generate()
    priv_pem = priv.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())
    pub_pem = priv.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo)
    kp = os.path.join(d, "wd-image.key")
    pp = os.path.join(d, "wd-image.pub")
    old = os.umask(0o077)
    try:
        with open(kp, "wb") as f:
            f.write(priv_pem)
        with open(pp, "wb") as f:
            f.write(pub_pem)
    finally:
        os.umask(old)
    print("private key: %s" % kp)
    print("public  key: %s" % pp)
    print("pubkey sha256: %s" % hashlib.sha256(pub_pem).hexdigest())


def cmd_sign(args):
    if not HAVE_CRYPTO:
        _die("python 'cryptography' package required")
    data = open(args.image, "rb").read()
    digest = hashlib.sha256(data).digest()
    msg = canonical_bytes(VERSION, 0, len(data), digest)
    key = _load_priv(args.key)
    sig = key.sign(msg)
    out = args.out or (args.image + ".sig")
    with open(out, "wb") as f:
        f.write(sig)
    print("signed %s (%d bytes, sha256 %s)" % (args.image, len(data), digest.hex()))
    print("signature: %s" % out)


def cmd_verify(args):
    if not HAVE_CRYPTO:
        _die("python 'cryptography' package required")
    data = open(args.image, "rb").read()
    sig = open(args.signature, "rb").read()
    digest = hashlib.sha256(data).digest()
    msg = canonical_bytes(VERSION, 0, len(data), digest)
    pub = _load_pub(args.pubkey)
    try:
        pub.verify(sig, msg)
    except Exception:
        print("FAIL: signature does not verify for %s" % args.image)
        return 1
    print("OK: %s verifies (sha256 %s)" % (args.image, digest.hex()))
    return 0


def cmd_wrap(args):
    if not HAVE_CRYPTO:
        _die("python 'cryptography' package required")
    data = open(args.image, "rb").read()
    digest = hashlib.sha256(data).digest()
    msg = canonical_bytes(VERSION, 0, len(data), digest)
    sig = _load_priv(args.key).sign(msg)
    head = HDR.pack(MAGIC, VERSION, 0, len(data), digest, len(sig))
    with open(args.out, "wb") as f:
        f.write(head)
        f.write(sig)
        f.write(data)
    print("wrapped %s -> %s (%d byte header + %d payload)"
          % (args.image, args.out, len(head) + len(sig), len(data)))
    print("header sha256: %s" % digest.hex())


def _read_wrapped(raw):
    if len(raw) < HDR.size:
        _die("not a wrapped image (too short)")
    magic, ver, flags, plen, digest, siglen = HDR.unpack_from(raw, 0)
    if magic != MAGIC:
        _die("bad magic %r (expected %r)" % (magic, MAGIC))
    off = HDR.size
    sig = raw[off:off + siglen]
    off += siglen
    payload = raw[off:off + plen]
    if len(payload) != plen:
        _die("truncated payload (%d of %d)" % (len(payload), plen))
    return ver, flags, plen, digest, sig, payload


def cmd_info(args):
    raw = open(args.wrapped, "rb").read()
    ver, flags, plen, digest, sig, payload = _read_wrapped(raw)
    actual = hashlib.sha256(payload).digest()
    print("magic:      %s" % MAGIC.decode())
    print("version:    %d" % ver)
    print("flags:      %d" % flags)
    print("payload:    %d bytes" % plen)
    print("sha256 hdr: %s" % digest.hex())
    print("sha256 act: %s" % actual.hex())
    print("digest:     %s" % ("MATCH" if digest == actual else "MISMATCH"))
    print("siglen:     %d" % len(sig))


def cmd_unwrap(args):
    raw = open(args.wrapped, "rb").read()
    ver, flags, plen, digest, sig, payload = _read_wrapped(raw)
    if hashlib.sha256(payload).digest() != digest:
        _die("payload digest mismatch; refusing to unwrap")
    if args.pubkey and HAVE_CRYPTO:
        pub = _load_pub(args.pubkey)
        pub.verify(sig, canonical_bytes(ver, flags, plen, digest))
        print("signature verified against %s" % args.pubkey)
    with open(args.out, "wb") as f:
        f.write(payload)
    print("unwrapped -> %s (%d bytes)" % (args.out, len(payload)))


def main():
    ap = argparse.ArgumentParser(prog="wd-image-tool", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    k = sub.add_parser("keygen")
    k.add_argument("-o", "--out", default=".")
    k.set_defaults(func=cmd_keygen)

    s = sub.add_parser("sign")
    s.add_argument("image")
    s.add_argument("-k", "--key", default="wd-image.key")
    s.add_argument("-o", "--out")
    s.set_defaults(func=cmd_sign)

    v = sub.add_parser("verify")
    v.add_argument("image")
    v.add_argument("-s", "--signature")
    v.add_argument("-p", "--pubkey", default="wd-image.pub")
    v.set_defaults(func=cmd_verify)

    w = sub.add_parser("wrap")
    w.add_argument("image")
    w.add_argument("-o", "--out", required=True)
    w.add_argument("-k", "--key", default="wd-image.key")
    w.set_defaults(func=cmd_wrap)

    i = sub.add_parser("info")
    i.add_argument("wrapped")
    i.set_defaults(func=cmd_info)

    u = sub.add_parser("unwrap")
    u.add_argument("wrapped")
    u.add_argument("-o", "--out", required=True)
    u.add_argument("-p", "--pubkey")
    u.set_defaults(func=cmd_unwrap)

    args = ap.parse_args()
    if args.cmd == "verify" and not args.signature:
        args.signature = args.image + ".sig"
    rc = args.func(args)
    sys.exit(rc or 0)


if __name__ == "__main__":
    main()
