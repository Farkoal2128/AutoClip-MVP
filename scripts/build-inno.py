"""Guard and compile the exact Windows Inno Setup candidate."""

import argparse
import ctypes
from ctypes import wintypes
from contextlib import ExitStack, contextmanager
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "installer" / "AutoClip.iss"
BOOTSTRAP = ROOT / "install.ps1"
PREFLIGHT = ROOT / "installer" / "preflight.ps1"
TOOL_ARCHIVE_HELPER = ROOT / "installer" / "install-tool-archive.ps1"
DOWNLOAD_HELPER = ROOT / "installer" / "download-artifact.ps1"
PYTHON_HELPER = ROOT / "installer" / "install-python.ps1"
CPU_NATIVE_HELPER = ROOT / "installer" / "install-cpu-native-artifact.py"
VC_RUNTIME_HELPER = ROOT / "installer" / "install-vc-runtime.ps1"
MSYS_BASE_HELPER = ROOT / "installer" / "install-msys2-base.ps1"
MSYS_EXTRACTOR = ROOT / "installer" / "extract-msys2-base.py"
MSYS_PACKAGES_HELPER = ROOT / "installer" / "install-msys2-packages.ps1"
RUNTIME_TOOLPATH_HELPER = ROOT / "installer" / "install-runtime-toolpath.ps1"
SOURCE_BUILD_HELPER = ROOT / "installer" / "run-source-build.ps1"
APP_HEALTH_HELPER = ROOT / "installer" / "verify-installed-app.ps1"
SETUP_RECEIPT_HELPER = ROOT / "installer" / "write-setup-receipt.ps1"
UNINSTALL_HELPER = ROOT / "installer" / "uninstall-owned-release.ps1"
REMOVAL_HELPER = ROOT / "installer" / "remove-owned-file.ps1"
UPDATER = ROOT / "update.ps1"
APP_UPDATER = ROOT / "update-app.ps1"
INITIAL_SELECTION = ROOT / "installer" / "initialize-selection.ps1"
MAINTENANCE_WORKER = ROOT / "installer" / "run-maintenance.ps1"
MAINTENANCE_SOURCE = ROOT / "installer" / "unified-maintenance.iss"
NOTICE = ROOT / "release" / "notices" / "inno-setup-7.1.0-LICENSE.txt"
NOTICE_PINS = {
    "inno-setup-7.1.0-LICENSE.txt": (1521, "2e5346868c2a18434489824e11d65c3031620f792fefc415d05f19cd441abf5c"),
    "uv-0.12.19-LICENSE-MIT.txt": (1077, "860e3d7a86b84e6a7012c7a635fc64df475cebc6cce34dfeb73a5982ec58176c"),
    "uv-0.12.19-LICENSE-APACHE.txt": (11357, "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"),
}
OUTPUT_NAME = "AutoClip-Setup-v1"


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


@contextmanager
def read_locked(path):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create = kernel.CreateFileW
    create.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                       wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                       wintypes.HANDLE)
    create.restype = wintypes.HANDLE
    close = kernel.CloseHandle
    close.argtypes = (wintypes.HANDLE,)
    close.restype = wintypes.BOOL
    # GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL.
    # Neither writers nor rename/delete requests can coexist with this handle.
    handle = create(str(path.absolute()), 0x80000000, 1, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        error = ctypes.get_last_error()
        raise ctypes.WinError(error, f"Cannot protect build input {path}: {ctypes.FormatError(error)}")
    try:
        yield
    finally:
        if not close(handle):
            raise ctypes.WinError(ctypes.get_last_error())


def build(args):
    if os.name != "nt":
        raise ValueError("Inno candidate builds require Windows input sharing locks")
    bootstrap = getattr(args, "bootstrap", None) or BOOTSTRAP
    native_artifact = getattr(args, "native_artifact", None)
    nvidia_native_artifact = getattr(args, "nvidia_native_artifact", None)
    inputs = (
        args.manifest, args.archive, args.iscc, SOURCE, bootstrap, PREFLIGHT,
        TOOL_ARCHIVE_HELPER, DOWNLOAD_HELPER, PYTHON_HELPER, MSYS_BASE_HELPER,
        MSYS_EXTRACTOR, MSYS_PACKAGES_HELPER, RUNTIME_TOOLPATH_HELPER,
        SOURCE_BUILD_HELPER, APP_HEALTH_HELPER, SETUP_RECEIPT_HELPER,
        UNINSTALL_HELPER, REMOVAL_HELPER, UPDATER, APP_UPDATER,
        INITIAL_SELECTION, MAINTENANCE_WORKER, MAINTENANCE_SOURCE,
        *(NOTICE.parent / name for name in (*NOTICE_PINS, "setup-tool-sources.md")),
        ROOT / "scripts" / "verify-installer-manifest.py", Path(__file__),
        *((native_artifact,) if native_artifact is not None else ()),
        *((nvidia_native_artifact,) if nvidia_native_artifact is not None else ()),
        *((CPU_NATIVE_HELPER, VC_RUNTIME_HELPER) if native_artifact is not None or nvidia_native_artifact is not None else ()),
    )
    with ExitStack() as locks:
        for path in dict.fromkeys(inputs):
            locks.enter_context(read_locked(path))
        pins = {path: digest(path) for path in inputs}
        return build_locked(args, pins)


def build_locked(args, pins):
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    verifier = ROOT / "scripts" / "verify-installer-manifest.py"
    bootstrap = getattr(args, "bootstrap", None) or BOOTSTRAP
    native_artifact = getattr(args, "native_artifact", None)
    nvidia_native_artifact = getattr(args, "nvidia_native_artifact", None)
    if manifest.get("nvidia_native_artifact") is not None and (native_artifact is None or nvidia_native_artifact is None):
        raise ValueError("BLOCKED: actual CPU and NVIDIA native artifacts are required for unified Setup")
    verification_command = [sys.executable, str(verifier), "--manifest", str(args.manifest),
                            "--archive", str(args.archive), "--profile", args.profile,
                            "--require-installable"]
    if native_artifact is not None:
        verification_command.extend(("--native-artifact", str(native_artifact)))
    if nvidia_native_artifact is not None:
        verification_command.extend(("--nvidia-native-artifact", str(nvidia_native_artifact)))
    if getattr(args, "allow_local_candidate", False):
        verification_command.append("--allow-local-candidate")
    check = subprocess.run(
        verification_command,
        capture_output=True, text=True, check=False,
    )
    if check.returncode:
        raise ValueError("BLOCKED: " + (check.stderr.strip() or check.stdout.strip()))

    compiler = manifest["compiler"]
    expected_size = compiler.get("compiler_executable_bytes", compiler["bytes"])
    expected_hash = compiler.get("compiler_executable_sha256", compiler["sha256"])
    if args.iscc.stat().st_size != expected_size or pins[args.iscc] != expected_hash:
        raise ValueError("Inno compiler executable identity differs from manifest")
    if not all(path.is_file() for path in (SOURCE, bootstrap, PREFLIGHT, TOOL_ARCHIVE_HELPER, DOWNLOAD_HELPER, PYTHON_HELPER, MSYS_BASE_HELPER, MSYS_EXTRACTOR, MSYS_PACKAGES_HELPER, RUNTIME_TOOLPATH_HELPER, SOURCE_BUILD_HELPER, APP_HEALTH_HELPER, SETUP_RECEIPT_HELPER, UNINSTALL_HELPER, REMOVAL_HELPER, UPDATER)):
        raise ValueError("Inno source, bootstrap, helper, or notice missing")
    notices = []
    for name in (*NOTICE_PINS, "setup-tool-sources.md"):
        data = (NOTICE.parent / name).read_bytes()
        size, sha256 = len(data), hashlib.sha256(data).hexdigest()
        if not size or (name in NOTICE_PINS and (size, sha256) != NOTICE_PINS[name]):
            raise ValueError(f"Setup notice identity differs: {name}")
        notices.append({"path": f"notices/{name}", "bytes": size, "sha256": sha256})

    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = args.output_dir / (OUTPUT_NAME + ".exe")
    receipt = args.output_dir / (OUTPUT_NAME + ".receipt.json")
    maintenance = args.output_dir / "AutoClip-Maintenance.exe"
    if output.exists() or receipt.exists() or maintenance.exists():
        raise ValueError("candidate or receipt already exists; use a new output directory")
    target = manifest["target_release"]
    mingit = next((item for item in manifest.get("build_prerequisites", [])
                   if item["identity"] == "Git for Windows"), {})
    uv = next((item for item in manifest.get("build_prerequisites", [])
               if item["identity"] == "uv"), {})
    ffmpeg = next((item for item in manifest.get("build_prerequisites", [])
                   if item["identity"] == "Gyan FFmpeg"), {})
    python = next((item for item in manifest.get("build_prerequisites", [])
                   if item["identity"] == "Python"), {})
    msys = next((item for item in manifest.get("build_prerequisites", [])
                 if item["identity"] == "MSYS2"), {})
    defines = {
        "ReleaseUrl": target["url"],
        "ReleaseSha256": target["sha256"],
        "ReleaseManifestSha256": target["manifest_sha256"],
        "ReleaseId": target["id"],
        "DependencyManifestSha256": pins[args.manifest],
        "BootstrapScriptPath": str(bootstrap),
        "DependencyManifestPath": str(args.manifest),
        "BootstrapSha256": pins[bootstrap],
        "PreflightSha256": pins[PREFLIGHT],
        "ToolArchiveHelperSha256": pins[TOOL_ARCHIVE_HELPER],
        "SecureDownloaderSha256": pins[DOWNLOAD_HELPER],
        "PythonHelperSha256": pins[PYTHON_HELPER],
        "PythonPrerequisiteHelperSha256": pins[PYTHON_HELPER],
        "MsysBaseHelperSha256": pins[MSYS_BASE_HELPER],
        "MsysExtractorSha256": pins[MSYS_EXTRACTOR],
        "MsysPackagesHelperSha256": pins[MSYS_PACKAGES_HELPER],
        "MsysArchiveSha256": msys.get("sha256", ""),
        "PythonSha256": python.get("sha256", ""),
        "PythonTermsUrl": python.get("terms_url", ""),
        "RuntimeToolPathHelperSha256": pins[RUNTIME_TOOLPATH_HELPER],
        "SourceBuildHelperSha256": pins[SOURCE_BUILD_HELPER],
        "AppHealthHelperSha256": pins[APP_HEALTH_HELPER],
        "SetupReceiptHelperSha256": pins[SETUP_RECEIPT_HELPER],
        "UninstallHelperSha256": pins[UNINSTALL_HELPER],
        "RemovalHelperSha256": pins[REMOVAL_HELPER],
        "UpdaterSha256": pins[UPDATER],
        "AppUpdaterSha256": pins[APP_UPDATER],
        "InitialSelectionSha256": pins[INITIAL_SELECTION],
        "MaintenanceWorkerSha256": pins[MAINTENANCE_WORKER],
        "SetupHelperRows": json.dumps([
            {"path": path.name, "bytes": path.stat().st_size, "sha256": pins[path]}
            for path in (UNINSTALL_HELPER, SETUP_RECEIPT_HELPER, REMOVAL_HELPER, SOURCE_BUILD_HELPER, UPDATER,
                         APP_UPDATER, INITIAL_SELECTION, MAINTENANCE_WORKER)
        ], separators=(",", ":")),
        "SetupNoticeRows": json.dumps(notices, separators=(",", ":")),
        "FfmpegSha256": ffmpeg.get("sha256", ""),
        "MinGitUrl": mingit.get("url", ""),
        "MinGitSha256": mingit.get("sha256", ""),
        "UvUrl": uv.get("url", ""),
        "UvSha256": uv.get("sha256", ""),
    }
    native = manifest.get("cpu_native_artifact")
    if native is not None:
        defines.update({
            "NativeCpuEnabled": "1", "CpuNativeIdentity": native["identity"],
            "CpuNativeRuntimeId": native["runtime_id"], "CpuNativeFilename": native["filename"],
            "CpuNativeSha256": native["sha256"], "CpuNativeBytes": str(native["bytes"]),
            "CpuNativeHelperSha256": pins[CPU_NATIVE_HELPER],
            "VcRuntimeHelperSha256": pins[VC_RUNTIME_HELPER],
        })
    nvidia_native = manifest.get("nvidia_native_artifact")
    if nvidia_native is not None:
        defines.update({
            "NativeNvidiaEnabled": "1", "NvidiaNativeIdentity": nvidia_native["identity"],
            "NvidiaNativeRuntimeId": nvidia_native["runtime_id"], "NvidiaNativeFilename": nvidia_native["filename"],
            "NvidiaNativeSha256": nvidia_native["sha256"], "NvidiaNativeBytes": str(nvidia_native["bytes"]),
            "CpuNativeHelperSha256": pins[CPU_NATIVE_HELPER],
            "VcRuntimeHelperSha256": pins[VC_RUNTIME_HELPER],
        })
    rows = json.loads(defines["SetupHelperRows"])
    rows.extend((
        {"path": "install.ps1", "bytes": bootstrap.stat().st_size, "sha256": pins[bootstrap]},
        {"path": "installer-dependencies-v1.json", "bytes": args.manifest.stat().st_size, "sha256": pins[args.manifest]},
    ))
    defines["SetupHelperRows"] = json.dumps(rows, separators=(",", ":"))
    # The retained maintenance alias is copied from the held original setup
    # during install. Its runtime receipt row uses that source hash, avoiding
    # a compiled executable's circular self-hash.
    with tempfile.TemporaryDirectory(prefix="autoclip-inno-inventory-") as temporary:
        inventory = Path(temporary) / "inventory.iss"
        inventory.write_text("".join(
            f"#define {key} '{defines.pop(key)}'\n"
            for key in ("SetupHelperRows", "SetupNoticeRows")
        ), encoding="utf-8")
        with read_locked(inventory):
            command = [str(args.iscc), f"--output-dir={args.output_dir}",
                       f"--output-filename={OUTPUT_NAME}", f"--include={inventory}"]
            command.extend(f"--define={key}={value}" for key, value in defines.items())
            command.append(str(SOURCE))
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    check=False)
    if result.returncode:
        raise RuntimeError(f"ISCC failed ({result.returncode}):\n{result.stdout}{result.stderr}")
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError("ISCC returned success without a nonempty setup executable")

    record = {
        "schema_version": 1,
        "qualification": "UNVERIFIED_CANDIDATE",
        "archive_sha256": pins[args.archive],
        "manifest_sha256": pins[args.manifest],
        "iscc_sha256": pins[args.iscc],
        "source_sha256": pins[SOURCE],
        "bootstrap_sha256": pins[bootstrap],
        "preflight_sha256": pins[PREFLIGHT],
        "tool_archive_helper_sha256": pins[TOOL_ARCHIVE_HELPER],
        "download_helper_sha256": pins[DOWNLOAD_HELPER],
        "python_helper_sha256": pins[PYTHON_HELPER],
        "msys_base_helper_sha256": pins[MSYS_BASE_HELPER],
        "msys_extractor_sha256": pins[MSYS_EXTRACTOR],
        "msys_packages_helper_sha256": pins[MSYS_PACKAGES_HELPER],
        "runtime_toolpath_helper_sha256": pins[RUNTIME_TOOLPATH_HELPER],
        "source_build_helper_sha256": pins[SOURCE_BUILD_HELPER],
        "app_health_helper_sha256": pins[APP_HEALTH_HELPER],
        "setup_receipt_helper_sha256": pins[SETUP_RECEIPT_HELPER],
        "uninstall_helper_sha256": pins[UNINSTALL_HELPER],
        "removal_helper_sha256": pins[REMOVAL_HELPER],
        "updater_sha256": pins[UPDATER],
        "app_updater_sha256": pins[APP_UPDATER],
        "initial_selection_sha256": pins[INITIAL_SELECTION],
        "maintenance_worker_sha256": pins[MAINTENANCE_WORKER],
        "maintenance_source_sha256": pins[MAINTENANCE_SOURCE],
        "maintenance_exe_sha256": digest(output),
        "maintenance_exe_bytes": output.stat().st_size,
        "notice_sha256": pins[NOTICE],
        "notices": notices,
        "builder_sha256": pins[Path(__file__)],
        "verifier_sha256": pins[verifier],
        "exe_sha256": digest(output),
        "exe_bytes": output.stat().st_size,
        "profile": args.profile,
    }
    if native is not None:
        record.update({"cpu_native_artifact": native,
                       "cpu_native_artifact_sha256": pins[native_artifact],
                       "cpu_native_artifact_bytes": native_artifact.stat().st_size,
                       "cpu_native_helper_sha256": pins[CPU_NATIVE_HELPER],
                       "vc_runtime_helper_sha256": pins[VC_RUNTIME_HELPER],
                       "bootstrap_path": str(bootstrap)})
    if nvidia_native is not None:
        record.update({"qualification": "UNQUALIFIED_CANDIDATE" if nvidia_native["qualification"] == "UNQUALIFIED_CANDIDATE" else "UNVERIFIED_CANDIDATE",
                       "nvidia_qualification": nvidia_native["qualification"],
                       "allow_local_candidate": bool(getattr(args, "allow_local_candidate", False)),
                       "nvidia_native_artifact": nvidia_native,
                       "nvidia_native_artifact_sha256": pins[nvidia_native_artifact],
                       "nvidia_native_artifact_bytes": nvidia_native_artifact.stat().st_size})
    receipt.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n",
                       encoding="utf-8")
    print(output)
    print(f"SHA-256 {record['exe_sha256']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--iscc", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--profile", choices=("cpu", "nvidia"), default="cpu")
    parser.add_argument("--native-artifact", type=Path)
    parser.add_argument("--nvidia-native-artifact", type=Path)
    parser.add_argument("--allow-local-candidate", action="store_true")
    parser.add_argument("--bootstrap", type=Path)
    args = parser.parse_args()
    try:
        build(args)
    except (OSError, ValueError, KeyError, RuntimeError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
