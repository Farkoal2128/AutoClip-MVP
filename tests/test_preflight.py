"""Run the real preflight with absent or broken native prerequisites."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PreflightTests(unittest.TestCase):
    def run_preflight(self, identity, broken, classification):
        with tempfile.TemporaryDirectory(prefix="autoclip-preflight-") as tmp:
            root = Path(tmp)
            tool = root / "broken.cmd"
            tool.write_text("@echo off\necho NATIVE_PROBE_FAILED 1>&2\nexit /b 1\n", encoding="ascii")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({
                "schema_version": 1,
                "build_prerequisites": [{"identity": identity, "version": "9.0.1",
                    "profile": "both", "delivery_classification": classification}],
                "external_assets": [],
            }), encoding="utf-8")
            report = root / "report.txt"
            wrapper = root / "run.ps1"
            wrapper.write_text("""param($Script, $Manifest, $Report, $Tool, $Broken)
function Get-Command { param($Name, $ErrorAction)
    if ($Broken -eq 'yes') { [pscustomobject]@{Source=$Tool} }
}
& $Script -ManifestPath $Manifest -ReportPath $Report -RequireNoBlocked
exit $LASTEXITCODE
""", encoding="utf-8")
            result = subprocess.run([
                "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", str(wrapper), str(ROOT / "installer/preflight.ps1"),
                str(manifest), str(report), str(tool), "yes" if broken else "no",
            ], capture_output=True, text=True, timeout=30)
            self.assertTrue(report.is_file(), result.stdout + result.stderr)
            self.assertIn(identity, report.read_text(encoding="utf-8-sig"))
            state = json.loads(result.stdout)
            self.assertFalse(state["ready"])
            self.assertEqual([r["identity"] for r in state["missing"]], [identity])
            return result, state

    def test_absent_downloadable_tool_produces_report(self):
        result, state = self.run_preflight("Gyan FFmpeg", False, "DIRECT_RECIPIENT_DOWNLOAD")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(state["blocked"])

    def test_broken_downloadable_tool_produces_report(self):
        result, state = self.run_preflight("Gyan FFmpeg", True, "DIRECT_RECIPIENT_DOWNLOAD")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(state["blocked"])

    def test_broken_system_driver_stays_blocked_with_report(self):
        result, state = self.run_preflight("NVIDIA GPU and driver", True, "SYSTEM_PROVIDED")
        self.assertEqual(result.returncode, 2)
        self.assertTrue(state["blocked"])


if __name__ == "__main__":
    unittest.main()
