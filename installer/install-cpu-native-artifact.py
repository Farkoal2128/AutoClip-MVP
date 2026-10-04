"""Validate and stage a pinned CPU artifact; never execute its contents."""

import argparse
import base64
import csv
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile
import tempfile
import zipfile


WHEELS = {"av-18.1.0-cp311-abi3-win_amd64.whl", "ctranslate2-4.8.2-cp311-cp311-win_amd64.whl"}
FFMPEG = {"avcodec-62", "avdevice-62", "avfilter-11", "avformat-62", "avutil-60", "swresample-6", "swscale-9"}
PINS = {
    "ffmpeg_source_sha256": "464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c",
    "pyav_source_sha256": "47bfc286e1bc9de7ab4681fc2b575cd2460a66919d31ffe1bd5aa54fae531a28",
    "onednn_commit": "64f6bcbcbab628e96f33a62c3e975f8535a7bde4",
    "ctranslate2_commit": "d44d2d069eb88c7b7804da864c10c201501cb4a9",
}
FLAGS = ("-DWITH_CUDA=OFF", "-DWITH_CUDNN=OFF", "-DWITH_MKL=OFF", "-DWITH_OPENBLAS=ON",
         "-DOPENMP_RUNTIME=COMP", "-DWITH_DNNL=ON", "-DWITH_RUY=OFF", "-DWITH_FLASH_ATTN=OFF")
MARKER = "native-artifact-manifest.json"
BINARY_SUFFIXES = {".dll", ".pyd", ".exe", ".msi", ".msix", ".lib", ".a", ".o", ".obj", ".so", ".dylib", ".whl", ".pyc", ".pyo", ".pdb"}
CACHES = {".git", ".venv", "__pycache__", "node_modules", "build-wheel-cache", "vendor-cache", "upstream-cache"}
RESERVED = re.compile(r"^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$)$", re.I)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field: " + key)
        result[key] = value
    return result


def document(data):
    return json.loads(data.decode("utf-8-sig"), object_pairs_hook=unique_object)


def checked_path(path):
    # Same existing reparse-ancestor rule as extract-msys2-base.py.
    path = Path(os.path.abspath(path))
    for cursor in (path, *path.parents):
        try:
            info = cursor.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("Reparse/symlink path prohibited: " + str(cursor))
    return path


def safe_name(name, seen):
    if not isinstance(name, str):
        raise ValueError("Archive path must be text")
    parts = name.removesuffix("/").split("/")
    if any(part in ("", ".", "..") or part.endswith((" ", "."))
           or re.search(r'[\x00-\x1f<>:"\\|?*\ud800-\udfff]', part)
           or RESERVED.fullmatch(part.split(".")[0].rstrip(" ")) for part in parts):
        raise ValueError("Unsafe Windows member path: " + repr(name))
    key = name.removesuffix("/").casefold()
    if key in seen:
        raise ValueError("Duplicate/case-colliding member: " + name)
    seen.add(key)


def zip_files(data, directories=False):
    files = {}
    seen = set()
    names = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            safe_name(member.filename, seen)
            names.append(member.filename.removesuffix("/"))
            kind = stat.S_IFMT(member.external_attr >> 16)
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR) or (member.is_dir() and not directories):
                raise ValueError("ZIP contains a directory or special/link member")
            if not member.is_dir():
                files[member.filename] = archive.read(member)
    # Directory spelling must also be unique when ZIP directories are implicit.
    paths = {}
    file_keys = {path.casefold() for path in files}
    for name in names:
        for part in (PurePosixPath(name), *PurePosixPath(name).parents):
            text = part.as_posix()
            if text == ".":
                continue
            key = text.casefold()
            if key in paths and paths[key] != text:
                raise ValueError("ZIP parent directory case alias")
            paths[key] = text
            if text != name and key in file_keys:
                raise ValueError("ZIP parent path conflicts with a file")
    return files


def source_payload(name, data, depth=0):
    path = PurePosixPath(name)
    if (path.suffix.lower() in BINARY_SUFFIXES or any(part.casefold() in CACHES for part in path.parts)
            or data.startswith((b"MZ", b"\x7fELF", b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"!<arch>\n"))):
        raise ValueError("Excluded binary/tool/cache outside wheels: " + name)
    is_zip = zipfile.is_zipfile(io.BytesIO(data))
    is_tar = data.startswith((b"\x1f\x8b", b"BZh", b"\xfd7zXZ\x00")) or data[257:262] == b"ustar"
    archive_name = name.lower().endswith((".zip", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2"))
    if not is_zip and not is_tar and not archive_name:
        return
    if depth >= 3:
        raise ValueError("Source archive nesting exceeds three levels")
    if is_zip or name.lower().endswith(".zip"):
        for member, content in zip_files(data, directories=True).items():
            source_payload(member, content, depth + 1)
    else:
        seen = set()
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
            for member in archive:
                safe_name(member.name, seen)
                if not member.isfile() and not member.isdir():
                    raise ValueError("Source TAR contains special/link member")
                if member.isfile():
                    source_payload(member.name, archive.extractfile(member).read(), depth + 1)


def wheel_record(name, data):
    # Stdlib portion of verify-native-source-wheels.py; PE imports remain producer qualification.
    files = zip_files(data, directories=True)
    records = [member for member in files if member.endswith(".dist-info/RECORD")]
    if len(records) != 1:
        raise ValueError("Exactly one wheel RECORD required")
    record = records[0]
    rows = list(csv.reader(io.StringIO(files[record].decode("utf-8"))))
    if any(len(row) != 3 for row in rows) or len({row[0] for row in rows}) != len(rows) or {row[0] for row in rows} != set(files):
        raise ValueError("Wheel RECORD inventory differs")
    for member, expected, size in rows:
        if member == record:
            if expected or size:
                raise ValueError("Wheel RECORD must not hash itself")
            continue
        content = files[member]
        encoded = base64.urlsafe_b64encode(hashlib.sha256(content).digest()).rstrip(b"=").decode("ascii")
        if expected != "sha256=" + encoded or size != str(len(content)):
            raise ValueError("Wheel RECORD byte identity differs: " + member)
    dlls = {member for member in files if member.lower().endswith(".dll")}
    if name.startswith("av-"):
        libraries = {next((library for library in FFMPEG if member.startswith("av.libs/" + library + "-")), "") for member in dlls}
        if len(dlls) != 7 or libraries != FFMPEG:
            raise ValueError("PyAV lacks precisely seven controlled FFmpeg DLLs")
    elif dlls != {"ctranslate2/ctranslate2.dll"}:
        raise ValueError("CTranslate2 DLL inventory differs")
    if any(PurePosixPath(member).suffix.lower() in BINARY_SUFFIXES - {".dll", ".pyd"}
           or any(part.casefold() in CACHES for part in PurePosixPath(member).parts) for member in files):
        raise ValueError("Wheel contains forbidden tool/cache payload")


def cuda_provenance(files):
    provenance = document(files["sources/cuda-runtime-provenance.json"])
    if (type(provenance.get("schema_version")) is not int or provenance["schema_version"] != 1
            or provenance.get("linkage") != "static" or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", provenance.get("cuda_version", ""))):
        raise ValueError("Static CUDA runtime provenance missing")
    libraries = provenance.get("libraries")
    if not isinstance(libraries, list) or not libraries or "cudart_static.lib" not in {row.get("name") for row in libraries}:
        raise ValueError("Static CUDA linker library inventory missing")
    for row in libraries:
        if (type(row.get("bytes")) is not int or row["bytes"] <= 0
                or not re.fullmatch(r"[a-f0-9]{64}", row.get("sha256", ""))
                or not isinstance(row.get("linker_path"), str) or not row["linker_path"]):
            raise ValueError("Static CUDA library provenance identity missing")
    paths = provenance.get("evidence_paths")
    notices = provenance.get("notice_paths")
    if not isinstance(paths, list) or not paths or not isinstance(notices, list) or not notices:
        raise ValueError("CUDA linker evidence/notices missing")
    for path in paths:
        safe_name(path, set())
        if not path.startswith("build/") or path not in files or not files[path]:
            raise ValueError("CUDA linker evidence absent")
    evidence = "\n".join(files[path].decode("utf-8-sig") for path in paths)
    if any(row["name"].casefold() not in evidence.casefold() for row in libraries):
        raise ValueError("CUDA library lacks actual linker evidence")
    for path in notices:
        safe_name(path, set())
        if not files.get("sources/" + path):
            raise ValueError("CUDA runtime notice absent")


def validate(raw, runtime_id, profile="cpu"):
    if profile not in ("cpu", "nvidia"):
        raise ValueError("Unsupported native profile")
    files = zip_files(raw)
    manifest = document(files[MARKER])
    required = {"schema_version": 1, "qualification": "UNQUALIFIED_CANDIDATE", "runtime_id": runtime_id,
                "profile": profile, "platform": "win_x64", "python": "cp311",
                "producer_receipt": "build/native-build-receipt.json", "provenance": "sources/provenance.json"}
    if (not isinstance(manifest, dict) or type(manifest.get("schema_version")) is not int
            or any(manifest.get(key) != value for key, value in required.items())):
        raise ValueError("Unsupported native artifact identity/profile/schema")
    rows = manifest.get("files")
    if not isinstance(rows, list):
        raise ValueError("Native manifest inventory missing")
    seen = set()
    for row in rows:
        name = row["path"]
        safe_name(name, seen)
        if (name not in files or name == MARKER or type(row.get("bytes")) is not int
                or row["bytes"] != len(files[name]) or row.get("sha256") != sha(files[name])):
            raise ValueError("Native manifest member identity differs")
    if {row["path"] for row in rows} != set(files) - {MARKER}:
        raise ValueError("Unindexed native artifact member")
    selected = {"wheels/" + name for name in WHEELS}
    if {name for name in files if name.startswith("wheels/")} != selected:
        raise ValueError("Native artifact must contain precisely two controlled wheels")
    for name, data in files.items():
        if name in selected:
            wheel_record(name.removeprefix("wheels/"), data)
        elif name != MARKER:
            if not name.startswith(("build/", "sources/")):
                raise ValueError("Unexpected artifact payload root")
            source_payload(name, data)
    receipt = document(files["build/native-build-receipt.json"])
    if (receipt.get("profile") != profile or receipt.get("install_nvidia_gpu") is not (profile == "nvidia")
            or any(receipt.get(key) != value for key, value in PINS.items())):
        raise ValueError("Native producer receipt profile/source pins differ")
    flags = receipt.get("cmake_arguments", [])
    required_flags = FLAGS if profile == "cpu" else tuple(flag.replace("WITH_CUDA=OFF", "WITH_CUDA=ON") for flag in FLAGS) + ("-DCUDA_DYNAMIC_LOADING=ON",)
    if (not isinstance(flags, list) or not all(isinstance(flag, str) for flag in flags) or not set(required_flags).issubset(flags)
            or any(flag.startswith(required.split("=", 1)[0] + "=") and flag != required for flag in flags for required in required_flags)):
        raise ValueError("Native producer receipt profile flags differ")
    expected_wheels = [{"filename": name, "bytes": len(files["wheels/" + name]), "sha256": sha(files["wheels/" + name])} for name in sorted(WHEELS)]
    if sorted(receipt.get("wheels", []), key=lambda row: row["filename"]) != expected_wheels:
        raise ValueError("Native producer receipt wheel identity differs")
    config = files["build/ffmpeg-config.mak"]
    if receipt.get("ffmpeg_config_sha256") != sha(config):
        raise ValueError("Native producer FFmpeg config identity differs")
    mak = config.decode("utf-8")
    header = files["build/ffmpeg-config.h"].decode("utf-8")
    log = files["build/ffmpeg-config.log"].decode("utf-8")
    for feature in ("GPL", "NONFREE", "LIBX264", "LIBX265"):
        if (f"!CONFIG_{feature}=yes" not in mak or f"CONFIG_{feature}=yes\n" in mak.replace(f"!CONFIG_{feature}=yes\n", "")
                or re.findall(r"(?m)^#define CONFIG_" + feature + r"\s+(\d+)\s*$", header) != ["0"]):
            raise ValueError("Unsafe actual FFmpeg config/header")
    if not all(flag in log for flag in ("--disable-autodetect", "--enable-shared", "--disable-static", "--disable-gpl", "--disable-nonfree", "--disable-libx264", "--disable-libx265")):
        raise ValueError("FFmpeg configure flags differ")
    associations = document(files["sources/source-associations.json"])
    if associations != manifest.get("source_associations") or type(associations.get("schema_version")) is not int or associations.get("schema_version") != 1:
        raise ValueError("Source associations differ")
    components = associations.get("components", [])
    if not {"ffmpeg", "pyav", "ctranslate2", "onednn"}.issubset({row.get("component") for row in components}):
        raise ValueError("Native source association missing")
    for row in components:
        for field in ("source_paths", "notice_paths"):
            if not isinstance(row.get(field), list) or not row[field]:
                raise ValueError("Source/notice association path missing")
            for name in row[field]:
                safe_name(name, set())
                target = "sources/" + name
                if not any(path == target or (field == "source_paths" and path.startswith(target + "/")) for path in files):
                    raise ValueError("Source/notice association absent")
                if field == "notice_paths" and not files[target]:
                    raise ValueError("Empty source notice")
    provenance = document(files["sources/provenance.json"])
    if not isinstance(provenance, dict) or not provenance:
        raise ValueError("Producer provenance missing")
    if profile == "nvidia":
        cuda_provenance(files)
    return files


def preflight(root, expected, require_complete=False):
    checked_path(root)
    if not root.exists():
        if require_complete:
            raise ValueError("Staging destination disappeared")
        return
    if not root.is_dir():
        raise ValueError("Staging destination must be a directory")
    directories = {parent.as_posix() for name in expected for parent in PurePosixPath(name).parents if parent.as_posix() != "."}
    pending = list(root.iterdir())
    actual = set()
    while pending:
        path = checked_path(pending.pop())
        name = path.relative_to(root).as_posix()
        if path.is_dir():
            if name not in directories:
                raise ValueError("Foreign staging directory: " + name)
            pending.extend(path.iterdir())
        elif not path.is_file() or name not in expected or path.read_bytes() != expected[name]:
            raise ValueError("Foreign/changed staging file: " + name)
        else:
            actual.add(name)
    if require_complete and actual - {MARKER} != set(expected) - {MARKER}:
        raise ValueError("Staged payload inventory is incomplete")


def publish(path, data):
    checked_path(path)
    if path.exists():
        if not path.is_file() or path.read_bytes() != data:
            raise ValueError("Changed staged output: " + str(path))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    checked_path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".cpu-stage-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        checked_path(path)
        os.link(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def stage(args):
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,127}", args.runtime_id):
        raise ValueError("Unsafe runtime identity")
    archive = checked_path(args.archive)
    if not archive.is_file() or type(args.archive_bytes) is not int or args.archive_bytes <= 0 or not re.fullmatch(r"[a-f0-9]{64}", args.archive_sha256):
        raise ValueError("Pinned regular archive/size/SHA256 required")
    raw = archive.read_bytes()
    if len(raw) != args.archive_bytes or sha(raw) != args.archive_sha256:
        raise ValueError("Archive size/SHA256 differs from caller pins")
    profile = getattr(args, "profile", "cpu")
    files = validate(raw, args.runtime_id, profile)
    wheels = checked_path(args.wheelhouse)
    sources = checked_path(args.source_output)
    if wheels == sources or wheels in sources.parents or sources in wheels.parents:
        raise ValueError("Staging roots must be separate")
    wheel_payload = {name.removeprefix("wheels/"): data for name, data in files.items() if name.startswith("wheels/")}
    source = {name: data for name, data in files.items() if not name.startswith("wheels/")}
    # Inspect both complete destinations before any mutation; partial identical retries are allowed.
    preflight(wheels, wheel_payload)
    preflight(sources, source)
    for name, data in sorted(wheel_payload.items()):
        publish(wheels / name, data)
    for name, data in sorted(source.items()):
        if name != MARKER:
            publish(sources / name, data)
    preflight(wheels, wheel_payload, require_complete=True)
    preflight(sources, source, require_complete=True)
    publish(sources / MARKER, files[MARKER])
    return {"status": "STAGED_VERIFIED", "runtime_id": args.runtime_id, "profile": profile,
            "archive_sha256": args.archive_sha256, "archive_bytes": args.archive_bytes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("archive", "wheelhouse", "source-output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    parser.add_argument("--archive-bytes", type=int, required=True)
    parser.add_argument("--runtime-id", required=True)
    parser.add_argument("--profile", choices=("cpu", "nvidia"), default="cpu")
    try:
        print(json.dumps(stage(parser.parse_args()), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile, tarfile.TarError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
