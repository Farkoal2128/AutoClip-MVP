"""Copy the manifest-authenticated MSYS2 base; never execute archive contents."""
import argparse
import ctypes
import hashlib
import json
import lzma
import os
from pathlib import Path
import re
import stat
import struct
import sys
import tarfile

NAME = "msys2-base-x86_64-20260611.tar.xz"
URL = "https://github.com/msys2/msys2-installer/releases/download/2026-06-11/" + NAME
MAX_MEMBERS = 16581
MAX_CONTENT_BYTES = 288055390
MAX_FILE_BYTES = 12326813
RESERVED = re.compile(r"^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$)$", re.I)


class ExtractionFailure(ValueError):
    def __init__(self, receipt, error):
        super().__init__(str(error))
        self.receipt = {**receipt, "status": "FAILED", "error": str(error)}


def digest_stream(stream):
    stream.seek(0)
    result = hashlib.file_digest(stream, "sha256").hexdigest()
    stream.seek(0)
    return result


def checked_path(path):
    """Reject every existing reparse ancestor without resolving through it."""
    path = Path(os.path.abspath(path))
    for cursor in (path, *path.parents):
        try:
            info = cursor.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise ValueError("Reparse path is prohibited: " + str(cursor))
    return path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate manifest field: " + key)
        result[key] = value
    return result


def validate_members(archive):
    members = []
    names = {}
    total = 0
    for member in archive:
        if len(members) >= MAX_MEMBERS:
            raise ValueError("Archive member count exceeds the pinned base limit")
        if member.type not in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE) or member.sparse is not None or any(
                key.startswith("GNU.sparse") for key in member.pax_headers):
            raise ValueError("Archive contains a link, device, sparse or unsupported member")
        if member.name.endswith("//"):
            raise ValueError("Archive contains an alternate member path")
        name = member.name.removesuffix("/") if member.isdir() else member.name
        parts = name.split("/")
        if parts[0] != "msys64" or any(
            part in ("", ".", "..") or part.endswith((" ", ".")) or
            re.search(r'[\x00-\x1f<>:"\\|?*\ud800-\udfff]', part) or
            RESERVED.fullmatch(part.split(".")[0].rstrip(" "))
            for part in parts
        ):
            raise ValueError("Archive contains an invalid Windows member path: " + repr(name))
        if name.casefold() in names:
            raise ValueError("Archive contains duplicate or case-colliding paths")
        if member.size < 0 or member.size > MAX_FILE_BYTES or (member.isdir() and member.size):
            raise ValueError("Archive member size exceeds the pinned base limit")
        total += member.size
        if total > MAX_CONTENT_BYTES:
            raise ValueError("Archive content exceeds the pinned base limit")
        names[name.casefold()] = (name, member.isdir())
        members.append((member, name))
    if names.get("msys64") != ("msys64", True):
        raise ValueError("Archive must contain one msys64 directory root")
    for _, name in members:
        cursor = name.rpartition("/")[0]
        while cursor:
            if names.get(cursor.casefold()) != (cursor, True):
                raise ValueError("Archive parent directory is missing or conflicts with a file")
            cursor = cursor.rpartition("/")[0]
    return members


def verify_inventory(parent, inventory):
    parent = checked_path(parent)
    expected = {row["path"]: row for row in inventory}
    actual = set()
    pending = [parent / "msys64"]
    while pending:
        current = checked_path(pending.pop())
        name = current.relative_to(parent).as_posix()
        row = expected.get(name)
        if row is None:
            raise ValueError("Extracted inventory contains unexpected path: " + name)
        info = current.lstat()
        if row["type"] == "directory":
            if not stat.S_ISDIR(info.st_mode):
                raise ValueError("Extracted inventory directory differs: " + name)
            pending.extend(current.iterdir())
        else:
            if not stat.S_ISREG(info.st_mode) or info.st_size != row["bytes"]:
                raise ValueError("Extracted inventory file differs: " + name)
            with current.open("rb") as stream:
                if digest_stream(stream) != row["sha256"]:
                    raise ValueError("Extracted inventory hash differs: " + name)
        actual.add(name)
    if actual != set(expected) or {p.name for p in parent.iterdir()} != {"msys64"}:
        raise ValueError("Extracted inventory has missing or extra paths")


def extract_base(manifest_path, manifest_sha256, archive_path, parent):
    receipt = {"schema_version": 1, "status": "FAILED", "extraction_state": "NOT_STARTED",
               "owned_root": None, "inventory": [], "acl_verified": False,
               "signature_verified": False, "native_initialization_performed": False,
               "executable_mode_qualification": "PENDING_NATIVE_WINDOWS_VERIFICATION"}
    try:
        if sys.version_info[:3] != (3, 11, 9) or struct.calcsize("P") != 8:
            raise ValueError("Exact Python 3.11.9 x64 is required")
        manifest_path = checked_path(manifest_path)
        raw = manifest_path.read_bytes()
        if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256) or hashlib.sha256(raw).hexdigest() != manifest_sha256:
            raise ValueError("Setup-bound manifest SHA-256 differs")
        document = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=unique_object)
        if not isinstance(document, dict) or type(document.get("schema_version")) is not int or document["schema_version"] != 1:
            raise ValueError("Unsupported dependency manifest schema")
        prerequisites = document.get("build_prerequisites")
        if not isinstance(prerequisites, list) or any(not isinstance(row, dict) for row in prerequisites):
            raise ValueError("Dependency prerequisite rows must be objects")
        rows = [row for row in prerequisites if str(row.get("identity", "")).casefold() == "msys2"]
        if len(rows) != 1:
            raise ValueError("Exactly one MSYS2 archive row is required")
        pin = rows[0]
        required = {"identity": "MSYS2", "version": "20260611", "filename": NAME,
                    "artifact_kind": "archive", "archive_format": "tar.xz", "url": URL,
                    "delivery_classification": "DIRECT_RECIPIENT_DOWNLOAD"}
        if any(pin.get(key) != value for key, value in required.items()):
            raise ValueError("Exact DIRECT MSYS2 base archive identity is required")
        if type(pin.get("bytes")) is not int or pin["bytes"] <= 0 or not re.fullmatch(r"[0-9a-f]{64}", str(pin.get("sha256", ""))):
            raise ValueError("Incomplete archive size or SHA-256 pin")
        archive_path = checked_path(archive_path)
        if archive_path.name != NAME:
            raise ValueError("Exact archive filename is required")
        original_parent = str(parent)
        if not re.fullmatch(r"[A-Za-z]:[\\/][A-Za-z0-9_\\/-]+", original_parent) or any(
                part in ("", ".", "..") for part in original_parent.replace("\\", "/")[3:].split("/")):
            raise ValueError("Parent must be a short ASCII absolute local Windows path")
        parent = checked_path(parent)
        if os.name != "nt" or ctypes.windll.kernel32.GetDriveTypeW(parent.anchor) != 3:
            raise ValueError("Parent must be on a local fixed Windows drive")
        msys_parent = "/" + parent.drive[0].lower() + parent.as_posix()[2:]
        if len((msys_parent + "/msys64/etc/pacman.d/ac-" + "0" * 32 + "/S.gpg-agent.browser").encode()) + 1 > 108:
            raise ValueError("Parent is too long for isolated MSYS2 agent sockets")
        if not parent.is_dir() or any(parent.iterdir()):
            raise ValueError("Existing parent must be an empty owned directory")
        with archive_path.open("rb") as source:
            if os.fstat(source.fileno()).st_size != pin["bytes"] or digest_stream(source) != pin["sha256"]:
                raise ValueError("Archive size or SHA-256 differs from manifest")
            receipt.update(manifest_sha256=manifest_sha256, archive_sha256=pin["sha256"], archive_bytes=pin["bytes"])
            with tarfile.open(fileobj=source, mode="r:xz") as archive:
                members = validate_members(archive)
                # Recheck immediately before owning any output. Caller must hold protected ACLs throughout.
                checked_path(parent)
                if any(parent.iterdir()):
                    raise ValueError("Parent changed before extraction")
                destination = parent / "msys64"
                destination.mkdir()
                receipt.update(owned_root=str(destination), extraction_state="PARTIAL")
                directories = sorted((item for item in members if item[0].isdir()), key=lambda item: item[1].count("/"))
                files = [item for item in members if item[0].isfile()]
                # Keep archive file order: backward seeks repeatedly decompress the XZ stream.
                for member, name in directories + files:
                    target = checked_path(parent / name)
                    if member.isdir():
                        if name != "msys64":
                            target.mkdir()
                        row = {"path": name, "type": "directory", "mode": member.mode & 0o777}
                    else:
                        result = hashlib.sha256()
                        with archive.extractfile(member) as incoming, target.open("xb") as outgoing:
                            remaining = member.size
                            while remaining:
                                chunk = incoming.read(min(1024 * 1024, remaining))
                                if not chunk:
                                    raise ValueError("Truncated archive file: " + name)
                                outgoing.write(chunk); result.update(chunk); remaining -= len(chunk)
                            if incoming.read(1):
                                raise ValueError("Archive file exceeds declared size")
                        row = {"path": name, "type": "file", "mode": member.mode & 0o777,
                               "bytes": member.size, "sha256": result.hexdigest()}
                    os.chmod(target, member.mode & 0o777)
                    os.utime(target, (member.mtime, member.mtime))
                    receipt["inventory"].append(row)
            if os.fstat(source.fileno()).st_size != pin["bytes"] or digest_stream(source) != pin["sha256"]:
                raise ValueError("Authenticated archive changed during extraction")
        if manifest_path.read_bytes() != raw:
            raise ValueError("Authenticated manifest changed during extraction")
        verify_inventory(parent, receipt["inventory"])
        receipt.update(status="VERIFIED_ARCHIVE_EXTRACTION", extraction_state="COMPLETE",
                       file_count=sum(row["type"] == "file" for row in receipt["inventory"]),
                       directory_count=sum(row["type"] == "directory" for row in receipt["inventory"]))
        return receipt
    except (OSError, ValueError, KeyError, TypeError, OverflowError, tarfile.TarError, lzma.LZMAError, KeyboardInterrupt) as error:
        raise ExtractionFailure(receipt, error) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--parent", required=True, type=Path)
    args = parser.parse_args()
    try:
        receipt = extract_base(args.manifest, args.manifest_sha256, args.archive, args.parent)
    except ExtractionFailure as error:
        print(json.dumps(error.receipt, sort_keys=True))
        print(error, file=sys.stderr)
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
