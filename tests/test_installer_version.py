"""Setup must install and advertise the release's actual application version."""
import io
import hashlib
import json
import runpy
import tempfile
import tarfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def runtime(version):
    wheel = io.BytesIO()
    with zipfile.ZipFile(wheel, "w") as archive:
        archive.writestr(f"autoclip-{version}.dist-info/METADATA",
                         f"Name: autoclip\nVersion: {version}\n")
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w") as archive:
        archive.writestr(f"wheelhouse/autoclip-{version}-py3-none-any.whl", wheel.getvalue())
    return result.getvalue()


class InstallerVersionTests(unittest.TestCase):
    def test_application_successor_replaces_stale_wheel_and_indexes(self):
        tool = runpy.run_path(str(ROOT / "scripts/rebind-distribution.py"))
        new = io.BytesIO()
        with zipfile.ZipFile(new, "w") as archive:
            archive.writestr("autoclip/__init__.py", b'__version__ = "1.1.1"\n')
            archive.writestr("autoclip-1.1.1.dist-info/METADATA", b"Name: autoclip\nVersion: 1.1.1\n")
        source = io.BytesIO()
        with tarfile.open(fileobj=source, mode="w:gz") as archive:
            raw = b'__version__ = "1.1.1"\n'
            entry = tarfile.TarInfo("autoclip-1.1.1/src/backend/autoclip/__init__.py")
            entry.size = len(raw)
            archive.addfile(entry, io.BytesIO(raw))
        files = {"wheelhouse/autoclip-1.0.0-py3-none-any.whl": self.old_wheel(),
                 "distribution-inventory.json": b'{"autoclip_wheels":["autoclip-1.0.0-py3-none-any.whl"]}',
                 "notices-and-source/sbom-packet-manifest.json": b'{"files":[],"file_count":0}'}
        release = {"release_id": "v1.0.0", "files": [tool["row"](n, b) for n,b in sorted(files.items())]}
        files["release-manifest.json"] = json.dumps(release).encode()
        baseline = io.BytesIO()
        with zipfile.ZipFile(baseline, "w") as archive:
            for name, raw in files.items():
                archive.writestr(name, raw)
        result, bootstrap = tool["replace_application"](baseline.getvalue(), b"autoclip==1.0.0 autoclip==1.0.0",
            "autoclip-1.1.1-py3-none-any.whl", new.getvalue(), "autoclip-1.1.1.tar.gz", source.getvalue())
        with zipfile.ZipFile(io.BytesIO(result)) as archive:
            self.assertNotIn("wheelhouse/autoclip-1.0.0-py3-none-any.whl", archive.namelist())
            self.assertEqual(archive.read("wheelhouse/autoclip-1.1.1-py3-none-any.whl"), new.getvalue())
            manifest = json.loads(archive.read("release-manifest.json"))
            self.assertEqual(manifest["application"]["version"], "1.1.1")
            for entry in manifest["files"]:
                raw = archive.read(entry["path"])
                self.assertEqual(entry["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(bootstrap, b"autoclip==1.1.1 autoclip==1.1.1")
        with self.assertRaisesRegex(ValueError, "Source/wheel"):
            self.check_source_mismatch(tool, baseline.getvalue(), new.getvalue())

    @staticmethod
    def check_source_mismatch(tool, baseline, wheel):
        source = io.BytesIO()
        with tarfile.open(fileobj=source, mode="w:gz") as archive:
            entry = tarfile.TarInfo("autoclip-1.1.1/src/backend/autoclip/__init__.py")
            entry.size = 5
            archive.addfile(entry, io.BytesIO(b"stale"))
        tool["replace_application"](baseline, b"autoclip==1.0.0 autoclip==1.0.0",
            "autoclip-1.1.1-py3-none-any.whl", wheel, "autoclip-1.1.1.tar.gz", source.getvalue())

    @staticmethod
    def old_wheel():
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, "w") as archive:
            archive.writestr("autoclip-1.0.0.dist-info/METADATA", b"Name: autoclip\nVersion: 1.0.0\n")
        return raw.getvalue()

    def test_setup_uses_packaged_version_and_rejects_stale_wheel(self):
        builder = runpy.run_path(str(ROOT / "scripts/build-inno.py"))
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "runtime.zip"
            archive.write_bytes(runtime("1.1.1"))
            self.assertEqual(builder["installer_version"](archive, "v1.1.1"), "1.1.1")
            archive.write_bytes(runtime("1.0.0"))
            with self.assertRaisesRegex(ValueError, "version"):
                builder["installer_version"](archive, "v1.1.1")

    def test_installer_feed_and_updater_use_same_immutable_url(self):
        tool = runpy.run_path(str(ROOT / "scripts/rebind-distribution.py"))
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, "w") as archive:
            archive.writestr("wheelhouse/autoclip-1.1.1-py3-none-any.whl", b"exact wheel")
            archive.writestr("release-manifest.json", b'{"release_id":"v1.1.1"}')
        feed, updater = tool["application_metadata"](
            raw.getvalue(), "v1.1.1", "installer-app-release-v1.1.1.json")
        self.assertIn(b"$manifestUrl = 'https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.1.1/installer-app-release-v1.1.1.json'", updater)
        self.assertIn(hashlib.sha256(feed).hexdigest().encode(), updater)
        builder = runpy.run_path(str(ROOT / "scripts/build-inno.py"))
        builder["verify_app_updater"](feed, updater, "v1.1.1", "1.1.1", hashlib.sha256(b"exact wheel").hexdigest())
        with self.assertRaisesRegex(ValueError, "updater"):
            builder["verify_app_updater"](feed, (ROOT / "installer/update-app.ps1").read_bytes(), "v1.1.1", "1.1.1", hashlib.sha256(b"exact wheel").hexdigest())
