"""Verify the exact release graph before it is used by a Windows setup build."""

import argparse
import hashlib
import importlib.util
import io
import json
import posixpath
import re
import stat
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit


IDENTITY = ("kind", "filename", "url", "bytes", "sha256")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def identity(entry):
    return tuple(entry[key] for key in IDENTITY)


def check_url(value):
    url = urlsplit(value)
    require(url.scheme == "https" and url.hostname and not url.username and not url.password,
            f"untrusted artifact URL: {value}")


def check_redirect_policy(entry):
    hosts = entry.get("redirect_hosts")
    url = urlsplit(entry["url"])
    require(isinstance(hosts, list) and hosts and all(
        isinstance(host, str) and re.fullmatch(r"[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}", host)
        for host in hosts) and url.scheme == "https" and url.hostname in hosts and
        url.port in (None, 443) and not url.username and not url.password and not url.fragment,
        f"missing or invalid exact redirect host policy: {entry['url']}")


def native_build_assets(recipe):
    """Read literal artifact pins from the archive's hash-checked build recipe."""
    sources = re.findall(
        r"Get-VerifiedSource '([^']+)' '([^']+)' (\d+) '([a-f0-9]{64})'", recipe)
    wheels = re.findall(
        r"@\('([^']+\.whl)', '([^']+)', (\d+), '([a-f0-9]{64})'\)", recipe)
    return [(name, url, int(size), digest) for name, url, size, digest in sources + wheels]


def check_msys2_base(base, require_installable):
    """Validate the single qualified archive route, including its child inputs."""
    filename = 'msys2-base-x86_64-20260611.tar.xz'
    url = 'https://github.com/msys2/msys2-installer/releases/download/2026-06-11/' + filename
    require(base.get('version') == '20260611' and base.get('architecture') == 'x64' and
            base.get('artifact_kind') == 'archive' and base.get('archive_format') == 'tar.xz' and
            base.get('filename') == filename and base.get('url') == url and
            base.get('bytes') == 53555380 and
            base.get('sha256') == 'a2d047e8ee213c3c6a49a8de427eb1069df12207c0422ff1b3cbb5c905c34221',
            'MSYS2 base differs from the exact reviewed archive identity')
    signature, key = base.get('signature', {}), base.get('installer_key', {})
    require(signature.get('filename') == filename + '.sig' and signature.get('url') == url + '.sig' and
            signature.get('bytes') == 566 and
            signature.get('sha256') == '076f5623b702d5016cf0253e1d14a6bd4870a90243243e96409b227f0d5bf70f',
            'MSYS2 archive signature identity differs')
    fingerprint = '0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC'
    require(key.get('filename') == 'installer-signer.asc' and key.get('bytes') == 52107 and
            key.get('sha256') == 'a247a92716ab322770e800793c10136dd22a6ea4691fdd2b9c72d4cfc5221082' and
            key.get('fingerprint') == fingerprint and
            key.get('url') == 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x' + fingerprint,
            'MSYS2 installer key identity differs')
    packages = base.get('packages', [])
    require(len(packages) == 5 and len({p.get('identity') for p in packages}) == 5,
            'MSYS2 requires five distinct pinned packages')
    children = [signature, key]
    for package in packages:
        name = package.get('filename', '')
        require(name == '{}-{}-{}.pkg.tar.zst'.format(
            package.get('identity'), package.get('version'), package.get('architecture')) and
            package.get('signature', {}).get('filename') == name + '.sig',
            'MSYS2 package/signature identity differs')
        children.extend([package, package['signature']])
    for artifact in [base] + children:
        require(artifact.get('delivery_classification') in ('BLOCKED', 'DIRECT_RECIPIENT_DOWNLOAD'),
                'MSYS2 archive inputs cannot be bundled or system-provided')
        check_redirect_policy(artifact)
        require(isinstance(artifact.get('bytes'), int) and artifact['bytes'] > 0 and
                re.fullmatch(r'[0-9a-f]{64}', artifact.get('sha256', '')),
                'MSYS2 archive input lacks an exact size/hash pin')
        if require_installable:
            require(artifact['delivery_classification'] == 'DIRECT_RECIPIENT_DOWNLOAD',
                    'MSYS2 archive or child route is blocked')


def check_zip_member(item, parent, archive):
    mode = stat.S_IFMT(item.external_attr >> 16) if item.create_system == 3 else 0
    if mode == stat.S_IFLNK:
        target = archive.read(item).decode("utf-8")
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(item.filename), target))
        require(target and not target.startswith("/") and "\\" not in target and
                ":" not in target and "\x00" not in target and
                resolved != ".." and not resolved.startswith("../"),
                f"unsafe archive link: {parent}!{item.filename}")
    else:
        require(mode in (0, stat.S_IFREG, stat.S_IFDIR),
                f"unsafe archive special file: {parent}!{item.filename}")


def inspect_nested(name, data, depth=0):
    """Reject executable payloads hidden in approved source/notice archives."""
    require(depth < 4, f"nested archive depth exceeded: {name}")
    lower = name.lower()
    if lower.endswith((".zip", ".whl")):
        with zipfile.ZipFile(io.BytesIO(data)) as nested:
            for item in nested.infolist():
                check_zip_member(item, name, nested)
            entries = [(item.filename, item.file_size,
                        lambda member=item: nested.read(member))
                       for item in nested.infolist() if not item.is_dir()]
            inspect_entries(name, entries, depth)
    elif lower.endswith((".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar")):
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as nested:
            for item in nested.getmembers():
                require(item.isfile() or item.isdir(),
                        f"unsafe archive link or special file: {name}!{item.name}")
            entries = [(item.name, item.size,
                        lambda member=item: nested.extractfile(member).read())
                       for item in nested.getmembers() if item.isfile()]
            inspect_entries(name, entries, depth)


def inspect_entries(parent, entries, depth):
    names = [name for name, _, _ in entries]
    require(len(names) == len(set(names)), f"duplicate nested member in {parent}")
    for name, size, read in entries:
        path = PurePosixPath(name)
        require(not path.is_absolute() and ".." not in path.parts and
                "\\" not in name and ":" not in name,
                f"unsafe nested member: {parent}!{name}")
        require(not path.name.lower().endswith((".exe", ".dll", ".whl")),
                f"prohibited nested binary: {parent}!{name}")
        if name.lower().endswith((".zip", ".whl", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar")):
            require(size <= 512 * 1024 * 1024, f"nested archive too large: {parent}!{name}")
            inspect_nested(parent + "!" + name, read(), depth + 1)


def check_cpu_native(outer, release, files, archive, profile, require_installable,
                     native_artifact, nvidia_native_artifact=None, allow_local_candidate=False):
    native = release.get("native_build", {})
    dual = native.get("delivery") == "publisher_native_artifacts"
    publisher = dual or native.get("delivery") == "publisher_cpu_with_source_nvidia"
    require((outer.get("cpu_native_artifact") is not None) == publisher,
            "publisher CPU native descriptor/delivery differs")
    require((outer.get("nvidia_native_artifact") is not None) == dual,
            "publisher NVIDIA native descriptor/delivery differs")
    if not publisher:
        require(native_artifact is None and nvidia_native_artifact is None,
                "native artifact supplied without publisher CPU descriptor")
        return
    tools = {"Visual Studio 2022 Build Tools", "Windows SDK", "Git for Windows", "MSYS2", "CUDA Toolkit", "NVIDIA CUDA Toolkit build components"}
    selected_native = outer.get("native_build_assets", [])
    prerequisites = outer.get("build_prerequisites", [])
    if dual:
        require(outer["cpu_native_artifact"].get("runtime_id") != outer["nvidia_native_artifact"].get("runtime_id"),
                "CPU and NVIDIA runtime identities must differ")
        require(not selected_native and not any(row.get("identity") in tools for row in prerequisites),
                "publisher native artifacts prohibit source build assets and developer prerequisites")
        require("build-native-from-source.ps1" not in files,
                "publisher native artifacts prohibit recipient source recipe")
    else:
        legacy_tools = tools - {"CUDA Toolkit", "NVIDIA CUDA Toolkit build components"}
        require(len(selected_native) == 9 and all(row.get("profile") == "nvidia" for row in selected_native),
                "publisher CPU source build assets must remain NVIDIA-only")
        require({row.get("identity") for row in prerequisites if row.get("identity") in legacy_tools} == legacy_tools,
                "publisher CPU route must retain NVIDIA build prerequisite identities")
        for row in prerequisites:
            if row.get("identity") in legacy_tools:
                require(row.get("profile") == "nvidia", "publisher CPU build prerequisites must remain NVIDIA-only")
                if row["identity"] in ("Visual Studio 2022 Build Tools", "Windows SDK"):
                    require(row.get("delivery_classification") == "BLOCKED", "unresolved NVIDIA vendor prerequisite must remain blocked")
    for expected_profile, actual_path in (("cpu", native_artifact), ("nvidia", nvidia_native_artifact)):
        descriptor = outer.get(expected_profile + "_native_artifact")
        label = "CPU" if expected_profile == "cpu" else "NVIDIA"
        if descriptor is None:
            require(actual_path is None, "native artifact supplied without " + label + " descriptor")
            continue
        require(isinstance(descriptor, dict) and native.get(expected_profile + "_artifact") == descriptor,
                label + " native artifact descriptor differs from release")
        runtime_id = descriptor.get("runtime_id", "")
        require(isinstance(runtime_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,127}", runtime_id)
                and descriptor.get("identity") == runtime_id,
                label + " native artifact runtime identity differs")
        require(descriptor.get("profile") == expected_profile and descriptor.get("delivery_classification") == "DIRECT_RECIPIENT_DOWNLOAD",
                label + " native artifact requires direct recipient " + label + " delivery")
        require(isinstance(descriptor.get("filename"), str) and re.fullmatch(r"[a-z0-9][a-z0-9._-]*\.zip", descriptor["filename"])
                and type(descriptor.get("bytes")) is int and descriptor["bytes"] > 0
                and re.fullmatch(r"[a-f0-9]{64}", descriptor.get("sha256", "")),
                label + " native artifact lacks exact filename/size/hash")
        check_url(descriptor["url"])
        require(urlsplit(descriptor["url"]).path.rsplit("/", 1)[-1] == descriptor["filename"],
                label + " native artifact URL filename differs")
        check_redirect_policy(descriptor)
        receipt_path = descriptor.get("qualification_receipt_path")
        require(receipt_path in files and files[receipt_path]["sha256"] == descriptor.get("qualification_receipt_sha256"),
                label + " native artifact qualification receipt is missing or differs")
        receipt = json.loads(archive.read(receipt_path))
        if expected_profile == "nvidia":
            require(descriptor.get("qualification") == receipt.get("decision"),
                    "NVIDIA artifact qualification contradicts distribution receipt")
        candidate = (dual and expected_profile == "nvidia" and allow_local_candidate
                     and descriptor.get("qualification") == "UNQUALIFIED_CANDIDATE")
        decision = "UNQUALIFIED_CANDIDATE" if candidate else "QUALIFIED_COMPONENT_DISTRIBUTION"
        require(type(receipt.get("schema_version")) is int and receipt["schema_version"] == 1
                and receipt.get("decision") == decision and isinstance(receipt.get("artifact"), dict)
                and all(receipt["artifact"].get(key) == descriptor[key] for key in ("runtime_id", "filename", "bytes", "sha256")),
                label + " native artifact exact distribution receipt differs")
        if require_installable and profile == expected_profile:
            require(actual_path is not None, "actual " + label + " native artifact is required for installable publisher " + label)
        if actual_path is not None:
            spec = importlib.util.spec_from_file_location("cpu_native_validator", Path(__file__).resolve().parents[1] / "installer/install-cpu-native-artifact.py")
            helper = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(helper)
            path = helper.checked_path(actual_path)
            require(path.name == descriptor["filename"] and path.is_file(), "actual " + label + " native artifact filename differs")
            raw = path.read_bytes()
            require(len(raw) == descriptor["bytes"] and sha256(raw) == descriptor["sha256"], "actual " + label + " native artifact size/SHA-256 differs")
            helper.validate(raw, runtime_id, expected_profile)


def check(outer_path, archive_path, profile="cpu", require_installable=False, native_artifact=None, nvidia_native_artifact=None, allow_local_candidate=False):
    outer = json.loads(outer_path.read_text(encoding="utf-8"))
    require(outer["schema_version"] == 1, "unsupported installer manifest schema")
    target = outer["target_release"]
    archive_bytes = archive_path.read_bytes()
    check_url(target["url"])
    if require_installable:
        require(target.get("delivery_classification") == "DIRECT_RECIPIENT_DOWNLOAD",
                "source release must use direct-recipient delivery")
        check_redirect_policy(target)
    require(len(archive_bytes) == target["bytes"], "release archive size mismatch")
    require(sha256(archive_bytes) == target["sha256"], "release archive SHA-256 mismatch")

    with zipfile.ZipFile(archive_path) as archive:
        for item in archive.infolist():
            check_zip_member(item, str(archive_path), archive)
        members = [item for item in archive.infolist() if not item.is_dir()]
        names = [item.filename for item in members]
        require(len(names) == len(set(names)), "duplicate archive member")
        for name in names:
            path = PurePosixPath(name)
            require(name == path.as_posix() and not path.is_absolute() and
                    not any(part in ("", ".", "..") for part in path.parts) and
                    "\\" not in name and ":" not in name,
                    f"unsafe archive member: {name}")
        require("release-manifest.json" in names, "release manifest missing")
        manifest_bytes = archive.read("release-manifest.json")
        require(sha256(manifest_bytes) == target["manifest_sha256"],
                "release manifest SHA-256 mismatch")
        release = json.loads(manifest_bytes)
        require(release["schema_version"] == 3, "unsupported release manifest schema")
        files = {entry["path"]: entry for entry in release["files"]}
        require(len(files) == len(release["files"]), "duplicate release manifest file")
        require(set(names) == set(files) | {"release-manifest.json"},
                "archive member is missing or unindexed")
        for name, entry in files.items():
            data = archive.read(name)
            require(len(data) == entry["bytes"] and sha256(data) == entry["sha256"],
                    f"archive member mismatch: {name}")

        check_cpu_native(outer, release, files, archive, profile, require_installable, native_artifact, nvidia_native_artifact, allow_local_candidate)

        selected_native = outer.get("native_build_assets", [])
        recipe_path = "build-native-from-source.ps1"
        expected_native = native_build_assets(archive.read(recipe_path).decode("utf-8-sig")) if recipe_path in files else []
        native_identity = lambda row: tuple(row[key] for key in ("filename", "url", "bytes", "sha256"))
        require(len(selected_native) == len(expected_native) and
                len({native_identity(row) for row in selected_native}) == len(selected_native) and
                {native_identity(row) for row in selected_native} == set(expected_native),
                "native build asset selection differs from the pinned recipe")
        for asset in selected_native:
            check_url(asset["url"])
            route = asset.get("delivery_classification")
            require(route in ("DIRECT_RECIPIENT_DOWNLOAD", "BLOCKED"),
                    f"invalid native build asset route: {asset['filename']}")
            if require_installable and asset.get("profile") in ("both", profile):
                require(route == "DIRECT_RECIPIENT_DOWNLOAD",
                        f"required native build asset is blocked: {asset['filename']}")
                check_redirect_policy(asset)

        publisher = outer["publisher_wheels"]
        require(publisher["delivery_classification"] == "DIRECT_RECIPIENT_DOWNLOAD",
                "publisher wheels must use direct-recipient delivery")
        publisher_path = publisher["manifest_path"]
        require(sha256(archive.read(publisher_path)) == publisher["sha256"],
                "publisher manifest SHA-256 mismatch")
        wheels = json.loads(archive.read(publisher_path))["wheels"]
        require(len(wheels) == publisher["count"] and wheels == release["publisher_wheels"],
                "publisher wheel identities differ")
        for wheel in wheels:
            check_url(wheel["url"])
            if require_installable:
                check_redirect_policy(dict(wheel, redirect_hosts=publisher.get("redirect_hosts")))
            require(wheel.get("delivery_policy") == "publisher" or
                    wheel.get("delivery_classification") == "DIRECT_RECIPIENT_DOWNLOAD",
                    f"unapproved publisher wheel route: {wheel['filename']}")

        inventory_bytes = archive.read("distribution-inventory.json")
        if "distribution_inventory_sha256" in target:
            require(sha256(inventory_bytes) == target["distribution_inventory_sha256"],
                    "distribution inventory SHA-256 mismatch")
        inventory = json.loads(inventory_bytes)
        require(inventory["publisher_wheels"] == [wheel["filename"] for wheel in wheels],
                "distribution inventory wheel names differ")
        if "publisher_wheel_identities" in inventory:
            require(inventory["publisher_wheel_identities"] == wheels,
                    "distribution inventory wheel identities differ")
        require(len(outer["external_assets"]) == len(release["external_assets"]) ==
                len(inventory["external_assets"]), "external asset selection differs")
        release_assets = {identity(row) for row in release["external_assets"]}
        inventory_assets = {identity(row) for row in inventory["external_assets"]}
        selected_assets = {identity(row) for row in outer["external_assets"]}
        require(release_assets == inventory_assets == selected_assets,
                "external asset identity differs")
        for asset in outer["external_assets"]:
            check_url(asset["url"])
            route = asset["delivery_classification"]
            require(route in ("DIRECT_RECIPIENT_DOWNLOAD", "BLOCKED"),
                    f"invalid external asset route: {asset['filename']}")
            if require_installable and route == "DIRECT_RECIPIENT_DOWNLOAD":
                check_redirect_policy(asset)
            if require_installable and route == "BLOCKED" and asset["profile"] in ("both", profile):
                raise ValueError(f"required external asset is blocked: {asset['filename']}")

        msys_bases = [row for row in outer.get('build_prerequisites', []) if row.get('identity') == 'MSYS2']
        require(len(msys_bases) <= 1, 'duplicate MSYS2 base identity')
        for base in msys_bases:
            check_msys2_base(base, require_installable and base.get('profile') in ('both', profile))

        if require_installable:
            for prerequisite in outer.get("build_prerequisites", []):
                if prerequisite["profile"] in ("both", profile):
                    name = prerequisite["identity"]
                    route = prerequisite["delivery_classification"]
                    require(route != "BLOCKED", f"required prerequisite is blocked: {name}")
                    require(route in ("DIRECT_RECIPIENT_DOWNLOAD", "SYSTEM_PROVIDED"),
                            f"invalid prerequisite route: {name}")
                    for field in ("version", "architecture", "publisher", "purpose",
                                  "detection", "post_install_check", "license_evidence"):
                        require(prerequisite.get(field), f"required prerequisite {name} lacks {field}")
                    if route == "DIRECT_RECIPIENT_DOWNLOAD":
                        require(prerequisite.get("url"), f"required prerequisite {name} lacks url")
                        check_url(prerequisite["url"])
                        check_redirect_policy(prerequisite)
                        require(isinstance(prerequisite.get("bytes"), int) and prerequisite["bytes"] > 0,
                                f"required prerequisite {name} lacks exact bytes")
                        require(re.fullmatch(r"[0-9a-f]{64}", prerequisite.get("sha256", "")),
                                f"required prerequisite {name} lacks exact sha256")
                        for field in ("installer_arguments", "success_exit_codes", "reboot_behavior"):
                            require(field in prerequisite,
                                    f"required prerequisite {name} lacks {field}")

        forbidden = {row["filename"].lower() for row in wheels + outer["external_assets"]}
        for name in names:
            basename = PurePosixPath(name).name.lower()
            require(basename not in forbidden and not basename.endswith((".exe", ".dll")),
                    f"prohibited binary bundled in release: {name}")
            if name.lower().endswith((".zip", ".whl", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar")):
                inspect_nested(name, archive.read(name))
        for entry in outer.get("setup_payload", []):
            require(entry["delivery_classification"] == "BUNDLE_ALLOWED",
                    f"unapproved setup payload: {entry['path']}")
            require(entry["path"] in files and files[entry["path"]]["sha256"] == entry["sha256"],
                    f"setup payload identity differs: {entry['path']}")

    print(f"verified {len(names)} release members, {len(wheels)} publisher wheels, "
          f"{len(outer['external_assets'])} external assets")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--profile", choices=("cpu", "nvidia"), default="cpu")
    parser.add_argument("--require-installable", action="store_true")
    parser.add_argument("--native-artifact", type=Path)
    parser.add_argument("--nvidia-native-artifact", type=Path)
    parser.add_argument("--allow-local-candidate", action="store_true")
    args = parser.parse_args()
    try:
        check(args.manifest, args.archive, args.profile, args.require_installable, args.native_artifact, args.nvidia_native_artifact, args.allow_local_candidate)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile,
            tarfile.TarError, json.JSONDecodeError) as error:
        print(f"installer manifest rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
