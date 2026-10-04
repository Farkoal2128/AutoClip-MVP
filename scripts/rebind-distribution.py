"""Rebind a pinned local package to an immutable AutoClip MVP release."""
import argparse
import copy
import io
import json
import re
import runpy
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRODUCER = runpy.run_path(str(ROOT / "scripts/build-publisher-cpu-release.py"))
sha = PRODUCER["sha"]
encoded = PRODUCER["encoded"]
pinned = PRODUCER["pinned"]
REPOSITORY = "https://github.com/Farkoal2128/AutoClip-MVP/releases/download/"


def row(name, raw):
    return dict(path=name, bytes=len(raw), sha256=sha(raw))


def application_metadata(archive_raw, release_id):
    with zipfile.ZipFile(io.BytesIO(archive_raw)) as archive:
        inner = archive.read("release-manifest.json")
        if json.loads(inner)["release_id"] != release_id:
            raise ValueError("App metadata runtime identity differs")
        wheels = [n for n in archive.namelist() if re.fullmatch(r"wheelhouse/autoclip-[^/]+\.whl", n)]
        if len(wheels) != 1:
            raise ValueError("Package must contain one exact AutoClip wheel")
        wheel = archive.read(wheels[0])
    feed = encoded(dict(schema_version=1, app_id="app-" + release_id,
        required_runtime=release_id, runtime_manifest_sha256=sha(inner),
        wheel_url=REPOSITORY + release_id + "/" + Path(wheels[0]).name,
        wheel_sha256=sha(wheel), wheel_size=len(wheel)))
    updater = (ROOT / "installer/update-app.ps1").read_bytes().decode("utf-8-sig")
    updater,count = re.subn(r"(?m)^\$expectedManifestSha256 = '[^']*'",
        lambda _: "$expectedManifestSha256 = '" + sha(feed) + "'", updater)
    if count != 1:
        raise ValueError("App updater manifest pin missing or duplicated")
    return feed, updater.encode()


def rebind(archive_raw, outer, bootstrap_raw, release_id, filename):
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,127}", release_id):
        raise ValueError("Unsafe release identity")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*\.zip", filename):
        raise ValueError("Unsafe archive filename")
    gate = PRODUCER["verifier"]()
    with zipfile.ZipFile(io.BytesIO(archive_raw)) as archive:
        for info in archive.infolist():
            gate["check_zip_member"](info, "input package", archive)
        files = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    release_raw = files.pop("release-manifest.json")
    release = json.loads(release_raw)
    if release.get("schema_version", 3) != 3 or sorted(release["files"], key=lambda r:r["path"]) != [row(n, b) for n,b in sorted(files.items())]:
        raise ValueError("Input package index differs")
    original_outer_sha256 = sha(encoded(outer))
    auxiliary = "notices-and-source/sbom-packet-manifest.json"
    if auxiliary in files:
        for entry in json.loads(files[auxiliary])["files"]:
            if row(entry["path"], files[entry["path"]]) != entry:
                raise ValueError("Input SBOM index differs: " + entry["path"])
    outer = copy.deepcopy(outer)
    old_id = release["release_id"]
    if release_id == old_id:
        raise ValueError("Migration needs a new immutable release identity")
    urls = {}
    for name, key in (("cpu_native_artifact", "cpu_artifact"), ("nvidia_native_artifact", "nvidia_artifact")):
        if name not in outer:
            continue
        original = outer[name]
        if original != release["native_build"][key]:
            raise ValueError("Input native descriptor differs")
        destination = REPOSITORY + release_id + "/" + original["filename"]
        urls[original["url"]] = destination
        outer[name]["url"] = destination
        release["native_build"][key] = copy.deepcopy(outer[name])
    # Retain the authenticated local installer contract in the operative updater.
    files["update.ps1"] = (ROOT / "installer/update.ps1").read_bytes()
    for name, raw in list(files.items()):
        if name.startswith(("notices-and-source/publisher-cpu/", "notices-and-source/publisher-nvidia/")) and name.endswith("/README.md"):
            for old, new in urls.items():
                raw = raw.replace(old.encode(), new.encode())
            files[name] = raw
    inventory = json.loads(files["distribution-inventory.json"])
    inventory["native_build"] = copy.deepcopy(release["native_build"])
    files["distribution-inventory.json"] = encoded(inventory)
    provenance_path = "notices-and-source/distribution-migration/" + release_id + ".json"
    if provenance_path in files:
        raise ValueError("Migration evidence already exists")
    files[provenance_path] = encoded(dict(schema_version=1, source_release_id=old_id,
        source_archive_sha256=sha(archive_raw), source_manifest_sha256=sha(release_raw),
        source_outer_sha256=original_outer_sha256, release_id=release_id, repository="Farkoal2128/AutoClip-MVP",
        updater_sha256=sha(files["update.ps1"]), migration_tool_sha256=sha(Path(__file__).read_bytes()),
        publication_state="UNPUBLISHABLE_REVIEW_PENDING",
        limits="Destination rebinding preserves component identities and qualification scope; local tests do not authorize publication."))
    if auxiliary in files:
        packet = json.loads(files[auxiliary])
        packet_rows = {r["path"]:r for r in packet["files"]}
        for name in packet_rows:
            if row(name, files[name]) != packet_rows[name]:
                packet_rows[name] = row(name, files[name])
        packet_rows[provenance_path] = row(provenance_path, files[provenance_path])
        packet["files"] = [packet_rows[n] for n in sorted(packet_rows)]
        packet["file_count"] = len(packet["files"])
        files[auxiliary] = encoded(packet)
    release["release_id"] = release_id
    release["files"] = [row(n, b) for n,b in sorted(files.items())]
    files["release-manifest.json"] = encoded(release)
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, raw in sorted(files.items()):
            archive.writestr(zipfile.ZipInfo(name, (2026,10,3,0,0,0)), raw, compress_type=zipfile.ZIP_DEFLATED)
    result = stream.getvalue()
    url = REPOSITORY + release_id + "/" + filename
    target = outer["target_release"]
    target.update(id=release_id, url=url, bytes=len(result), sha256=sha(result),
                  manifest_sha256=sha(files["release-manifest.json"]),
                  distribution_inventory_sha256=sha(files["distribution-inventory.json"]))
    for payload in outer.get("setup_payload", []):
        payload["sha256"] = sha(files[payload["path"]])
    text = bootstrap_raw.decode("utf-8-sig").replace("Farkoal2128/autoclip-runtime", "Farkoal2128/AutoClip-MVP")
    for name, value in (("releaseUrl",url), ("expectedArchiveSha256",sha(result)),
                        ("expectedManifestSha256",target["manifest_sha256"]), ("releaseId",release_id)):
        text,count = re.subn(r"(?m)^\$" + name + r" = '[^']*'", lambda _: "$" + name + " = '" + value + "'", text)
        if count != 1:
            raise ValueError("Bootstrap pin assignment missing or duplicated: " + name)
    return result, outer, text.encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("archive", "manifest", "bootstrap", "output-dir", "native-artifact"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--nvidia-native-artifact", type=Path)
    for name in ("archive-sha256", "manifest-sha256", "bootstrap-sha256", "release-id", "filename"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--allow-local-candidate", action="store_true")
    args = parser.parse_args()
    inputs = [pinned(args.archive,args.archive_sha256), pinned(args.manifest,args.manifest_sha256), pinned(args.bootstrap,args.bootstrap_sha256)]
    gate = PRODUCER["verifier"]()
    # Validate exact pinned bytes in staging, rather than reopening mutable inputs.
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        archive = stage / args.filename
        policy = stage / "manifest.json"
        archive.write_bytes(inputs[0]); policy.write_bytes(inputs[1])
        for profile in (("cpu","nvidia") if args.nvidia_native_artifact else ("cpu",)):
            gate["check"](policy,archive,profile,True,args.native_artifact,args.nvidia_native_artifact,args.allow_local_candidate)
        result, manifest, bootstrap = rebind(inputs[0],json.loads(inputs[1]),inputs[2],args.release_id,args.filename)
        archive.write_bytes(result); policy.write_bytes(encoded(manifest))
        for profile in (("cpu","nvidia") if args.nvidia_native_artifact else ("cpu",)):
            gate["check"](policy,archive,profile,True,args.native_artifact,args.nvidia_native_artifact,args.allow_local_candidate)
        feed, updater = application_metadata(result,args.release_id)
        outputs = {args.filename:result,"installer-dependencies-v1.json":encoded(manifest),
                   "install.ps1":bootstrap,"app-release.json":feed,"update-app.ps1":updater}
        if args.output_dir.exists():
            raise ValueError("Use a new immutable output directory")
        args.output_dir.mkdir(parents=True)
        for name, raw in outputs.items():
            with (args.output_dir/name).open("xb") as output:
                output.write(raw)
        print(json.dumps([row(str(args.output_dir/n),raw) for n,raw in outputs.items()],indent=2))


if __name__ == "__main__":
    main()
