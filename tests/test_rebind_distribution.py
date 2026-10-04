import hashlib
import io
import json
import runpy
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RebindTests(unittest.TestCase):
    def test_rebind_preserves_native_and_wheel_bytes_and_indexes(self):
        tool = runpy.run_path(str(ROOT / "scripts/rebind-distribution.py"))
        sha = lambda raw: hashlib.sha256(raw).hexdigest()
        descriptor = dict(filename="native.zip", runtime_id="native-runtime-v1", identity="native-runtime-v1", bytes=12, sha256="a" * 64, url="https://github.com/Farkoal2128/autoclip-runtime/releases/download/old/native.zip")
        native = dict(cpu_artifact=descriptor)
        files = {"wheelhouse/app.whl": b"exact app wheel", "update.ps1": b"old updater", "distribution-inventory.json": json.dumps(dict(native_build=native)).encode()}
        release = dict(release_id="old", native_build=native, files=[dict(path=n, bytes=len(b), sha256=sha(b)) for n, b in files.items()])
        files["release-manifest.json"] = json.dumps(release).encode()
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as z:
            for n, b in files.items():
                z.writestr(n, b)
        outer = dict(target_release=dict(id="old"), cpu_native_artifact=descriptor)
        bootstrap = b"\n".join(("$" + n + " = 'old'").encode() for n in ("releaseUrl", "expectedArchiveSha256", "expectedManifestSha256", "releaseId"))
        raw, policy, standalone = tool["rebind"](stream.getvalue(), outer, bootstrap, "mvp-v1", "mvp.zip")
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            self.assertEqual(z.read("wheelhouse/app.whl"), b"exact app wheel")
            self.assertEqual(z.read("update.ps1"), (ROOT / "installer/update.ps1").read_bytes())
            result = json.loads(z.read("release-manifest.json"))
            for row in result["files"]:
                data = z.read(row["path"])
                self.assertEqual((row["bytes"], row["sha256"]), (len(data), sha(data)))
            rebound = result["native_build"]["cpu_artifact"]
            self.assertEqual({k:v for k,v in rebound.items() if k != "url"}, {k:v for k,v in descriptor.items() if k != "url"})
            self.assertEqual(rebound["url"], "https://github.com/Farkoal2128/AutoClip-MVP/releases/download/mvp-v1/native.zip")
            self.assertEqual(json.loads(z.read("distribution-inventory.json"))["native_build"], result["native_build"])
        self.assertEqual(policy["target_release"]["sha256"], sha(raw))
        self.assertIn(sha(raw).encode(), standalone)
        self.assertNotIn(b"Farkoal2128/autoclip-runtime", standalone)

    def test_app_metadata_and_updater_pin_match_final_package(self):
        tool = runpy.run_path(str(ROOT / "scripts/rebind-distribution.py"))
        stream = io.BytesIO()
        wheel = "autoclip-0.1.0.dev0-py3-none-any.whl"
        with zipfile.ZipFile(stream, "w") as z:
            z.writestr("wheelhouse/" + wheel, b"exact wheel")
            z.writestr("release-manifest.json", b'{"release_id":"mvp-v1"}')
        feed, updater = tool["application_metadata"](stream.getvalue(), "mvp-v1")
        manifest = json.loads(feed)
        self.assertEqual(manifest["required_runtime"], "mvp-v1")
        self.assertEqual(manifest["runtime_manifest_sha256"], hashlib.sha256(b'{"release_id":"mvp-v1"}').hexdigest())
        self.assertEqual(manifest["wheel_url"], "https://github.com/Farkoal2128/AutoClip-MVP/releases/download/mvp-v1/" + wheel)
        self.assertEqual(manifest["wheel_sha256"], hashlib.sha256(b"exact wheel").hexdigest())
        self.assertEqual(manifest["wheel_size"], 11)
        pin = __import__("re").search(rb"(?m)^\$expectedManifestSha256 = '([^']+)'", updater).group(1)
        self.assertEqual(pin.decode(), hashlib.sha256(feed).hexdigest())
        self.assertNotIn(b"Farkoal2128/autoclip-runtime", updater)


if __name__ == "__main__":
    unittest.main()
