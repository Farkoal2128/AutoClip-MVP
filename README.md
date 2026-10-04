# AutoClip for Windows

Windows installer and maintenance files for AutoClip. This repository is the distribution home for future Windows releases.

## Download and install

Download [AutoClip-Setup-v1.exe](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/AutoClip-Setup-v1.exe) from the [v1.0.0 release](https://github.com/Farkoal2128/AutoClip-MVP/releases/tag/v1.0.0). This full Windows release consolidates the accepted prerequisite, yt-dlp settings and Twitch download fixes. See the [validation record](docs/releases/v1.0.0.md) for exact package and local test evidence.

Run the installer and choose **Install AutoClip**. CPU is the default profile. The NVIDIA profile uses prebuilt native wheels and checks compatible GPU prerequisites. Review the prerequisite terms shown by Setup. **Launch AutoClip** on the final page opens the application.

For a v1.0.0 installation, run the same installer again to choose **Update AutoClip** or **Roll back the application**. Remove AutoClip through Windows Installed apps. Shared prerequisites, user data, and files not owned by the installation are preserved.

### Updating an existing MVP or draft installation

Download [AutoClip-Update-v1.0.0.zip](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/AutoClip-Update-v1.0.0.zip), finish or cancel current processing, quit AutoClip, and extract the ZIP. Follow its `UPDATE.md` to apply the 1.0.0 application with your installed updater. This retains the verified MVP runtime, installed maintenance files and previous application for rollback. The new installer refuses a different existing runtime before writing files; do not use it to migrate a prerelease installation.

## What this repository contains

Installer source, its required PowerShell/Python helpers, release validation/build scripts, notices, and focused distribution checks. Application/runtime archives and native wheels are versioned release assets rather than files stored in Git. Application development remains in [myAutoclip](https://github.com/Farkoal2128/myAutoclip).

AutoClip-owned payload downloads and application-update metadata use this repository. Dependencies acquired directly from their original publishers retain their publisher URLs. Payloads are verified against pinned SHA-256 digests and sizes; failed verification or application health checks prevent activation.

## Build and verification

See [distribution requirements](docs/requirements/distribution.md) for the pinned release inputs and build workflow. Builds require Windows, Python 3.11+, and the exact Inno Setup compiler recorded in the dependency manifest. A build receipt identifies the executable and every bundled helper. Local candidate builds do not establish publication readiness.

Release validation covers installation, a healthy update, rejection of a failed-health update, rollback, uninstall, and preservation of unrelated files. The release record states which machine and acquisition paths were tested. Local host results do not claim clean-machine or VM coverage.

## Licensing

The installer and AutoClip-authored files are distributed under the [MIT License](LICENSE), copyright 2026 Jad Ghazi. Third-party software keeps its own licenses; this repository's MIT license does not replace them.

Setup tool notices are in [release/notices](release/notices). Runtime/native release archives carry their component notices, source material, build provenance, and file inventories. NVIDIA prerequisites are separately acquired under NVIDIA's terms. Consult the exact release's license and source index for the selected components.
