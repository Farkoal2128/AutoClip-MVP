"""Focused destination and compiler-closure regression checks (stdlib only)."""
import re
import runpy
import unittest
import subprocess
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Farkoal2128/AutoClip-MVP"


class DistributionTests(unittest.TestCase):
    def test_public_defaults_are_published_or_fail_closed(self):
        feed = ROOT / "app-release.json"
        if feed.exists():
            updater = (ROOT / "installer/update-app.ps1").read_text(encoding="utf-8-sig")
            pin = re.search(r"(?m)^\$expectedManifestSha256 = '([^']+)'", updater).group(1)
            self.assertEqual(pin, hashlib.sha256(feed.read_bytes()).hexdigest())
            manifest = json.loads(feed.read_bytes())
            self.assertTrue(manifest["wheel_url"].startswith("https://github.com/" + REPOSITORY + "/releases/download/"))
        else:
            result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-File", str(ROOT / "install.ps1"), "-ReleaseInfo"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("No installer release has been published", result.stderr)

    def test_operational_defaults_use_mvp(self):
        install = (ROOT / "install.ps1").read_text(encoding="utf-8-sig")
        updater = (ROOT / "installer/update-app.ps1").read_text(encoding="utf-8-sig")
        release = re.search(r"(?m)^\$releaseUrl = '([^']+)'", install).group(1)
        feed = re.search(r"(?m)^\$manifestUrl = '([^']+)'", updater).group(1)
        self.assertTrue(release.startswith("https://github.com/" + REPOSITORY + "/releases/download/"), release)
        self.assertEqual(feed, "https://raw.githubusercontent.com/" + REPOSITORY + "/main/app-release.json")
        self.assertIn("Farkoal2128/AutoClip-MVP/releases/download/", updater)
        for name in ("install.ps1", "installer/update.ps1", "installer/update-app.ps1"):
            self.assertNotIn("Farkoal2128/autoclip-runtime", (ROOT / name).read_text(encoding="utf-8-sig"))

    def test_compiler_closure_is_present(self):
        builder = runpy.run_path(str(ROOT / "scripts/build-inno.py"))
        for key, value in builder.items():
            if isinstance(value, Path) and key != "ROOT":
                self.assertTrue(value.is_file(), str(value))
        for name in (*builder["NOTICE_PINS"], "setup-tool-sources.md"):
            self.assertTrue((ROOT / "release/notices" / name).is_file())

    def test_checkout_layout_and_inno_sources_resolve(self):
        for source, destination in (
            ("update.ps1", "installer/update.ps1"),
            ("update-app.ps1", "installer/update-app.ps1"),
            ("Start-AutoClip.ps1", "installer/Start-AutoClip.ps1"),
            ("installer-dependencies-v1.json", "release/installer-dependencies-v1.json"),
            ("THIRD_PARTY_NOTICES.md", "release/THIRD_PARTY_NOTICES.md"),
            ("BUILDING.md", "docs/BUILDING.md"),
        ):
            self.assertTrue((ROOT / destination).is_file(), destination)
            self.assertFalse((ROOT / source).exists(), source)
        for name in ("install.ps1", "app-release.json", "README.md", "LICENSE", "CONTRIBUTING.md", "SECURITY.md"):
            self.assertTrue((ROOT / name).is_file(), name)
        source = ROOT / "installer/AutoClip.iss"
        paths = re.findall(r'^Source: "([^"{]+)";', source.read_text(encoding="utf-8-sig"), re.MULTILINE)
        self.assertTrue(paths)
        for path in paths:
            self.assertTrue((source.parent / path.replace("\\", "/")).is_file(), path)


if __name__ == "__main__":
    unittest.main()
