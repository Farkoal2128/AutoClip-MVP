# AutoClip for Windows

Windows installer and maintenance files for AutoClip. This repository is the distribution home for future Windows releases.

## Download and install

Download [AutoClip-Setup-v1.exe](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/AutoClip-Setup-v1.exe) from the [v1.0.0 release](https://github.com/Farkoal2128/AutoClip-MVP/releases/tag/v1.0.0). This full Windows release consolidates the accepted prerequisite, yt-dlp settings and Twitch download fixes. See the [validation record](docs/releases/v1.0.0.md) for exact package and local test evidence.

Run the installer and choose **Install AutoClip**. CPU is the default profile. The NVIDIA profile uses prebuilt native wheels and checks compatible GPU prerequisites. Review the prerequisite terms shown by Setup. **Launch AutoClip** on the final page opens the application.

For a v1.0.0 installation, run the same installer again to choose **Update AutoClip** or **Roll back the application**. Remove AutoClip through Windows Installed apps. Shared prerequisites, user data, and files not owned by the installation are preserved.

### Updating an existing MVP or draft installation

Download [AutoClip-Update-v1.0.0.zip](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/AutoClip-Update-v1.0.0.zip), finish or cancel current processing, quit AutoClip, and extract the ZIP. Follow its `UPDATE.md` to apply the 1.0.0 application with your installed updater. This retains the verified MVP runtime, installed maintenance files and previous application for rollback. The new installer refuses a different existing runtime before writing files; do not use it to migrate a prerelease installation.

## What this repository contains

Installer source, its required PowerShell/Python helpers, release validation/build scripts, notices, and focused distribution checks. Application/runtime archives and native wheels are versioned release assets rather than files stored in Git.
AutoClip-owned payload downloads and application-update metadata use this repository. Dependencies acquired directly from their original publishers retain their publisher URLs. Payloads are verified against pinned SHA-256 digests and sizes; failed verification or application health checks prevent activation.

| Location | Contents |
| --- | --- |
| `installer/` | Inno source, prerequisite and maintenance helpers, updater scripts, runtime launcher template |
| `release/` | Dependency manifest, third-party overview, tool notices |
| `scripts/` | Build, packaging, and validation tools |
| `tests/` | Distribution regression tests |
| `docs/` | Build guide, distribution requirements, release records |

The public `install.ps1` bootstrap and `app-release.json` update feed stay at the root so existing callers keep working. Installed helper names and release-asset filenames are independent of this checkout layout.

## Source code

Download the [AutoClip v1.0.0 application source](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/autoclip-1.0.0.tar.gz). It includes the Python backend, editable React/TypeScript frontend, dependency manifests, and MIT license. Installer source is in this repository; the [v1.0.0 tag](https://github.com/Farkoal2128/AutoClip-MVP/tree/v1.0.0) contains the source used for the published installer.

## Build and verification

See [the build guide](docs/BUILDING.md) for exact v1.0.0 inputs and Windows build commands, and [distribution requirements](docs/requirements/distribution.md) for release rules. Installer builds require Windows, Python 3.11+, and the exact Inno Setup compiler recorded in the dependency manifest. A build receipt identifies the executable and every bundled helper. Local candidate builds do not establish publication readiness.

Release validation covers installation, a healthy update, rejection of a failed-health update, rollback, uninstall, and preservation of unrelated files. The release record states which machine and acquisition paths were tested. Local host results do not claim clean-machine or VM coverage.

## Licensing

AutoClip-authored files are distributed under the [MIT License](LICENSE). The original AutoClip copyright notice, copyright 2026 Jad Ghazi, is retained. Third-party software keeps its own licenses; this repository's MIT license does not replace them.

The [third-party overview](release/THIRD_PARTY_NOTICES.md) and [setup tool notices](release/notices) are in `release/`. Runtime/native release archives carry their component notices, source material, build provenance, and file inventories. NVIDIA prerequisites are separately acquired under NVIDIA's terms. Consult the exact release's license and source index for the selected components.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for changes and contributor credits, and [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Contributors

- **[Farkoal2128](https://github.com/Farkoal2128)** — repository owner, maintainer, and release owner of this derived Windows build.
- **[Jad Ghazi (@artbyjazi)](https://github.com/artbyjazi)** — author of the [original AutoClip](https://github.com/artbyjazi/autoclip), on which this build is based.
- **[Codex (@codex)](https://github.com/codex)** — OpenAI AI development assistant; contributed implementation, testing, packaging, and documentation assistance under the maintainer's direction. Maintainer review and release decisions remain with Farkoal2128.
