#!/usr/bin/env python3
"""Offline SSH-backup patcher for Viettel vAP-120WD OEM vAP-1.82-230928.

Requires Python 3.9+ and openssl on PATH. Never connects to or flashes a router.
Three modes: lan-only (default), legacy-like, legacy-exact (unsafe).
"""
from __future__ import annotations

import argparse
import base64
import binascii
import copy
import difflib
import gzip
import hashlib
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

MAX_INPUT = 64 * 1024 * 1024
MAX_TAR = 128 * 1024 * 1024
SECTION_RE = re.compile(rb"^\s*config\s+([\w-]+)(?:\s+['\"]([^'\"]+)['\"])?\s*$")
OPTION_RE = re.compile(rb"^\s*option\s+([\w-]+)\s+['\"]([^'\"]*)['\"]\s*$")


class BackupError(Exception):
    """Input format mismatch or unsafe/unsupported patching operation."""


def serial_password(serial: str) -> str:
    """Reverse-engineered OEM algorithm: ROT8 uppercase A-Z, digits unchanged."""
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", serial):
        raise BackupError("Serial must contain 1–128 ASCII letters/digits/_/-")
    return "".join(chr((ord(c) - 65 + 8) % 26 + 65) if "A" <= c <= "Z" else c
                   for c in serial)


def decode_envelope(data: bytes) -> bytes:
    if not data.startswith(b"Salted__"):
        try:
            data = base64.b64decode(re.sub(rb"\s+", b"", data), validate=True)
        except (ValueError, binascii.Error) as exc:
            raise BackupError("Input must be Base64/OpenSSL Salted__ or raw Salted__") from exc
    if not data.startswith(b"Salted__") or len(data) < 32 or (len(data) - 16) % 16:
        raise BackupError("Invalid OpenSSL Salted__ envelope")
    return data


def openssl_crypt(data: bytes, password: str, *, encrypt: bool) -> bytes:
    # -md md5 is CRUCIAL for OEM compatibility; openssl 3 defaults to sha256.
    cmd = ["openssl", "enc", "-aes-256-cbc", "-md", "md5", "-pass", "env:VAP120WD_KEY"]
    cmd.extend(["-e", "-salt", "-a"] if encrypt else ["-d"])
    try:
        run = subprocess.run(cmd, input=data, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, check=False,
                             env={**os.environ, "VAP120WD_KEY": password})
    except FileNotFoundError as exc:
        raise BackupError("OpenSSL CLI was not found on PATH") from exc
    if run.returncode != 0:
        raise BackupError("OpenSSL failed (wrong serial, damaged backup or different firmware): "
                          + run.stderr.decode("utf-8", "replace").strip())
    return run.stdout


def decrypt_backup(raw: bytes, password: str) -> bytes:
    """Return verified gzip TAR bytes; keep the plaintext in memory only."""
    if len(raw) > MAX_INPUT:
        raise BackupError("Input backup exceeds size limit")
    plain = openssl_crypt(decode_envelope(raw), password, encrypt=False)
    if len(plain) < 34 or not re.fullmatch(rb"[0-9a-fA-F]{32}", plain[:32]):
        raise BackupError("Decrypted data lacks a 32-character MD5 prefix")
    gz = plain[32:]
    if hashlib.md5(gz).hexdigest().encode("ascii") != plain[:32].lower():
        raise BackupError("Vendor MD5 verification failed")
    # Validate full gzip/tar structure without extracting anything to disk.
    read_members(gz)
    return gz


def read_members(gz: bytes):
    if not gz.startswith(b"\x1f\x8b"):
        raise BackupError("Expected gzip TAR after MD5 prefix")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(gz)) as reader:
            tar_blob = reader.read(MAX_TAR + 1)
    except (OSError, EOFError) as exc:
        raise BackupError("Gzip stream is invalid") from exc
    if len(tar_blob) > MAX_TAR:
        raise BackupError("Uncompressed TAR exceeds size limit")
    items = []
    try:
        with tarfile.open(fileobj=io.BytesIO(tar_blob), mode="r:") as tar:
            for member in tar:
                name = member.name.removeprefix("./").rstrip("/")
                if member.name.startswith("/") or ".." in name.split("/"):
                    raise BackupError("Unsafe TAR path encountered")
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    raise BackupError("Unsupported TAR entry type")
                data = tar.extractfile(member).read() if member.isfile() else None
                items.append([copy.copy(member), name, data])
    except (tarfile.TarError, EOFError) as exc:
        raise BackupError("Invalid TAR stream") from exc
    if not items:
        raise BackupError("Empty TAR")
    return items


def get_member(items, path: str):
    found = [x for x in items if x[1] == path and x[0].isfile()]
    if len(found) != 1:
        raise BackupError(f"Expected exactly one file {path}, found {len(found)}")
    return found[0]


def sections_from_firewall(raw: bytes):
    lines = raw.splitlines(keepends=True)
    sections = []
    for index, line in enumerate(lines):
        stripped = line.rstrip(b"\r\n")
        head = SECTION_RE.fullmatch(stripped)
        if head:
            if sections:
                sections[-1]["end"] = index
            sections.append({"type": head.group(1).decode(),
                             "id": (head.group(2) or b"").decode(),
                             "start": index, "end": len(lines), "options": {},
                             "indices": {}})
        elif sections:
            option = OPTION_RE.fullmatch(stripped)
            if option:
                key, value = option.group(1).decode(), option.group(2).decode()
                s = sections[-1]
                if key in s["options"]:
                    raise BackupError(f"Duplicate firewall option in section {s['id']}: {key}")
                s["options"][key] = value
                s["indices"][key] = index
    return lines, sections


def required_section(sections, typ: str, identifier: str):
    matches = [s for s in sections if s["type"] == typ and s["id"] == identifier]
    if len(matches) != 1:
        raise BackupError(f"Expected one {typ} '{identifier}', found {len(matches)}")
    return matches[0]


def require_options(s, **expected):
    for key, value in expected.items():
        if s["options"].get(key) != value:
            raise BackupError(f"Unexpected {s['id']}.{key}: {s['options'].get(key)!r}, expected {value!r}")


def substitute_quoted_value(line: bytes, old: str, new: str, *, key: str | None = None) -> bytes:
    """Update exactly one quoted UCI value, preserving other text and EOL."""
    if key is None:
        pattern = rb"^(\s*config\s+[\w-]+\s+)(['\"])([^'\"]+)(\2)(\s*\r?\n?)$"
    else:
        pattern = rb"^(\s*option\s+" + re.escape(key.encode()) + rb"\s+)(['\"])([^'\"]*)(\2)(\s*\r?\n?)$"
    match = re.fullmatch(pattern, line)
    if match is None or match.group(3) != old.encode():
        raise BackupError("Ambiguous/malformed UCI line: " + line.decode("utf-8", "replace").strip())
    return match.group(1) + match.group(2) + new.encode() + match.group(4) + match.group(5)


def patch_firewall(raw: bytes, mode: str) -> bytes:
    lines, sections = sections_from_firewall(raw)
    defaults = required_section(sections, "defaults", "")
    wan = required_section(sections, "zone", "zone_wan_df_route")
    mgmt = required_section(sections, "rule", "access_from_wan")
    require_options(defaults, forward="REJECT")
    require_options(wan, name="wandfroute", input="REJECT", forward="REJECT")
    require_options(mgmt, src="wandfroute", proto="tcp", dest_port="80 443", target="REJECT")

    rule_specs = (
        ("ssh_lan_reject", "lan", "22", "Reject-SSH-From-Lan"),
        ("telnet_lan_reject", "lan", "23", "Reject-Telnet-From-Lan"),
        ("ssh_wan_reject", "wandfroute", "22", "Accept-SSH-From-Wan"),
        ("telnet_wan_reject", "wandfroute", "23", "Accept-Telnet-From-Wan"),
    )
    for rid, src, port, label in rule_specs:
        require_options(required_section(sections, "rule", rid),
                        name=label, src=src, proto="tcp", dest_port=port,
                        target="REJECT", enabled="1")

    changes = {}
    def edit(typ: str, identifier: str, *, new_id=None, options=None):
        s = required_section(sections, typ, identifier)
        if new_id is not None:
            changes[s["start"]] = substitute_quoted_value(
                lines[s["start"]], identifier, new_id)
        for field, (old, new) in (options or {}).items():
            if s["options"].get(field) != old:
                raise BackupError(f"Unexpected current value for {identifier}.{field}")
            idx = s["indices"].get(field)
            if idx is None or idx in changes:
                raise BackupError(f"Missing or duplicate option {identifier}.{field}")
            changes[idx] = substitute_quoted_value(lines[idx], old, new, key=field)

    edit("rule", "ssh_lan_reject", new_id="ssh_lan_accept", options={
        "name": ("Reject-SSH-From-Lan", "Accept-SSH-From-Lan"),
        "target": ("REJECT", "ACCEPT"),
    })
    if mode in ("legacy-like", "legacy-exact"):
        edit("defaults", "", options={"forward": ("REJECT", "ACCEPT")})
        edit("zone", "zone_wan_df_route", options={
            "input": ("REJECT", "ACCEPT"), "forward": ("REJECT", "ACCEPT")})
        edit("rule", "access_from_wan", options={"target": ("REJECT", "ACCEPT")})
        edit("rule", "telnet_lan_reject", new_id="telnet_lan_accept", options={
            "name": ("Reject-Telnet-From-Lan", "Accept-Telnet-From-Lan"),
            "target": ("REJECT", "ACCEPT")})
        edit("rule", "telnet_wan_reject", new_id="telnet_wan_accept",
             options={"target": ("REJECT", "ACCEPT")})
        edit("rule", "ssh_wan_reject", new_id="ssh_wan_accept",
             options={"target": ("REJECT", "ACCEPT")})
    if len(changes) != (14 if mode in ("legacy-like", "legacy-exact") else 3):
        raise BackupError("Unexpected number of firewall changes")
    return b"".join(changes.get(i, line) for i, line in enumerate(lines))


def patch_shadow(raw: bytes, reference_shadow: bytes | None = None) -> bytes:
    lines = raw.splitlines(keepends=True)
    root_idx = [i for i, ln in enumerate(lines) if ln.startswith(b"root:")]
    admin_idx = [i for i, ln in enumerate(lines) if ln.startswith(b"admin:")]
    http_idx = [i for i, ln in enumerate(lines) if ln.startswith(b"http:")]
    if len(root_idx) != 1 or len(admin_idx) != 1 or len(http_idx) != 1:
        raise BackupError("Unexpected shadow accounts (root, admin, http expected once each)")
    i = root_idx[0]
    eol = b"\r\n" if lines[i].endswith(b"\r\n") else b"\n" if lines[i].endswith(b"\n") else b""
    fields = lines[i].rstrip(b"\r\n").split(b":")
    if len(fields) != 9 or not fields[1] or fields[1] in (b"!", b"*", b"!!"):
        raise BackupError("Root's original shadow hash is missing or unsupported")
    fields[1], fields[2] = b"", b"0"
    lines[i] = b":".join(fields) + eol
    if http_idx[0] != len(lines) - 1 or not lines[http_idx[0]].endswith(b"\n"):
        raise BackupError("Unsupported shadow entry order / missing newline")
    lines.append(lines[http_idx[0]])
    if reference_shadow is not None:
        reference_admin = [ln for ln in reference_shadow.splitlines() if ln.startswith(b"admin:")]
        if len(reference_admin) != 1:
            raise BackupError("Expected exactly one admin account in reference")
        new_fields = reference_admin[0].split(b":")
        i = admin_idx[0]
        old_eol = b"\r\n" if lines[i].endswith(b"\r\n") else b"\n" if lines[i].endswith(b"\n") else b""
        old_fields = lines[i].rstrip(b"\r\n").split(b":")
        if len(new_fields) != 9 or not new_fields[1] or len(old_fields) != 9:
            raise BackupError("Invalid reference admin shadow entry")
        old_fields[1] = new_fields[1]
        lines[i] = b":".join(old_fields) + old_eol
    return b"".join(lines)


def normalized_files(items):
    result = {}
    for member, name, blob in items:
        if not name or name == "." or member.isdir():
            continue
        if name in result:
            raise BackupError("Duplicate TAR member: " + name)
        result[name] = (member.type, blob if member.isfile() else member.linkname,
                        member.mode, member.uid, member.gid,
                        member.mtime, member.uname, member.gname)
    return result


def pack_archive(items) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for meta, _, data in items:
            member = copy.copy(meta)
            if member.isfile():
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))
            else:
                tar.addfile(member)
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0,
                       compresslevel=9) as gz:
        gz.write(buf.getvalue())
    return output.getvalue()


def encrypt_backup(gz: bytes, password: str) -> bytes:
    plaintext = hashlib.md5(gz).hexdigest().encode("ascii") + gz
    return openssl_crypt(plaintext, password, encrypt=True)


def transform(original_raw: bytes, password: str, mode: str,
              reference_raw: bytes | None = None):
    original = read_members(decrypt_backup(original_raw, password))
    old_files = normalized_files(original)
    modified = [[copy.copy(m), n, d] for m, n, d in original]
    firewall = get_member(modified, "etc/config/firewall")
    original_firewall = firewall[2]
    firewall[2] = patch_firewall(firewall[2], mode)
    firewall[0].size = len(firewall[2])
    changed = {"etc/config/firewall"}
    reference = None
    if reference_raw is not None:
        reference = read_members(decrypt_backup(reference_raw, password))
    if mode in ("legacy-like", "legacy-exact"):
        shadow = get_member(modified, "etc/shadow")
        ref_shadow = None
        if mode == "legacy-exact":
            if reference is None:
                raise BackupError("legacy-exact requires --reference")
            ref_shadow = get_member(reference, "etc/shadow")[2]
        shadow[2] = patch_shadow(shadow[2], ref_shadow)
        shadow[0].size = len(shadow[2])
        changed.add("etc/shadow")
    newer = normalized_files(modified)
    if old_files.keys() != newer.keys():
        raise BackupError("TAR file inventory changed unexpectedly")
    actual_changes = {name for name in old_files if old_files[name] != newer[name]}
    if actual_changes != changed:
        raise BackupError(f"Unexpected modified members: {sorted(actual_changes)}")
    if reference is not None and mode in ("legacy-like", "legacy-exact"):
        ref = normalized_files(reference)
        verify_files = changed if mode == "legacy-exact" else {"etc/config/firewall"}
        for name in verify_files:
            if name not in ref or newer[name][1] != ref[name][1]:
                raise BackupError(f"Result does not match reference's {name}")
    compressed = pack_archive(modified)
    result = encrypt_backup(compressed, password)
    verified = normalized_files(read_members(decrypt_backup(result, password)))
    if verified != newer:
        raise BackupError("Encrypted output failed offline round-trip validation")
    return result, original_firewall, firewall[2], sorted(changed)


def write_new(path: Path, content: bytes):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as dest:
            dest.write(content)
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Viettel vAP-120WD OEM 1.82 offline SSH backup patcher")
    ap.add_argument("-i", "--input", type=Path, required=True,
                    help="Original encrypted OEM backup")
    ap.add_argument("-o", "--output", type=Path,
                    help="New encrypted backup (never overwrites an existing file)")
    ap.add_argument("--serial", required=True, help="Serial printed on your router")
    ap.add_argument("--mode", choices=("lan-only", "legacy-like", "legacy-exact"),
                    default="lan-only")
    ap.add_argument("--reference", type=Path,
                    help="Historical OPEN_SSH backup; required for legacy-exact")
    ap.add_argument("--acknowledge-insecure", action="store_true",
                    help="Required for legacy modes: opens WAN/Telnet and empties root hash")
    ap.add_argument("--dry-run", action="store_true", help="Validate and preview changes, no output")
    args = ap.parse_args(argv)
    if not args.output and not args.dry_run:
        ap.error("Provide --output or --dry-run")
    if args.mode in ("legacy-like", "legacy-exact") and not args.acknowledge_insecure:
        ap.error("legacy modes require --acknowledge-insecure")
    if args.mode == "legacy-exact" and not args.reference:
        ap.error("legacy-exact requires --reference")
    try:
        password = serial_password(args.serial)
        raw = args.input.read_bytes()
        reference_raw = args.reference.read_bytes() if args.reference else None
        output, before, after, changed = transform(raw, password, args.mode, reference_raw)
        print("Mode:", args.mode)
        print("Changed files:", ", ".join(changed))
        print("\n".join(difflib.unified_diff(
            before.decode("utf-8", "replace").splitlines(),
            after.decode("utf-8", "replace").splitlines(),
            fromfile="original/firewall", tofile=args.mode + "/firewall", lineterm="")))
        if args.mode != "lan-only":
            print("WARNING: legacy mode opens WAN/Telnet and removes root password hash.")
            if args.mode == "legacy-exact":
                print("WARNING: admin password hash is copied from reference.")
        if args.dry_run:
            print("Dry run complete; no output written.")
            return 0
        if args.input.resolve() == args.output.resolve():
            raise BackupError("Refusing to overwrite source backup")
        write_new(args.output, output)
        print("Output:", args.output)
        print("SHA256:", hashlib.sha256(output).hexdigest())
        print("Offline decrypt/MD5/TAR verification: PASS")
        print("NOT tested on a live OEM router. NEVER import into OpenWrt.")
        return 0
    except (BackupError, OSError, EOFError, ValueError, tarfile.TarError) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
