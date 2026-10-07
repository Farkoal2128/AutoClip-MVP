# Building AutoClip on Windows

## Current and future installer releases

Every public app update must include a full Setup for that version, plus the
app-update ZIP for existing installations. Start with exact published runtime,
dependency manifest and bootstrap bytes. Reuse unchanged qualified native archives.
Supply the new wheel and matching editable source, with independently verified
SHA-256 values, to `scripts/rebind-distribution.py`:

```powershell
python scripts/rebind-distribution.py `
  --archive ../prior/autoclip-windows-v1.0.0.zip --archive-sha256 <verified-prior-archive-hash> `
  --manifest ../prior/installer-dependencies-v1.json --manifest-sha256 <verified-prior-manifest-hash> `
  --bootstrap ../prior/install.ps1 --bootstrap-sha256 <verified-prior-bootstrap-hash> `
  --application-wheel ../app/autoclip-1.1.1-py3-none-any.whl --application-wheel-sha256 <verified-wheel-hash> `
  --application-source ../app/autoclip-1.1.1.tar.gz --application-source-sha256 <verified-source-hash> `
  --native-artifact ../prior/autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip `
  --nvidia-native-artifact ../prior/autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip `
  --release-id v1.1.1 --filename autoclip-windows-v1.1.1.zip --output-dir ../release-inputs
python scripts/build-inno.py `
  --manifest ../release-inputs/installer-dependencies-v1.json `
  --archive ../release-inputs/autoclip-windows-v1.1.1.zip `
  --bootstrap ../release-inputs/install.ps1 `
  --app-updater ../release-inputs/update-app.ps1 `
  --app-manifest ../release-inputs/installer-app-release-v1.1.1.json `
  --iscc ../inno/ISCC.exe `
  --native-artifact ../prior/autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip `
  --nvidia-native-artifact ../prior/autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip `
  --output-dir ../candidate
python -m unittest discover -s tests -v
```

Replace the version and prior inputs for subsequent releases. Both output
directories must be new. The packager replaces the sole app wheel, compares
declared dependencies, verifies packaged app bytes against the source, retains
native qualification scope and notices, and regenerates inventories and pins.
A dependency change requires separate graph/component qualification.
The compiler derives `AutoClip-Setup-v1.1.1.exe` and its displayed version from
the wheel; a stale wheel, release mismatch or wrong updater/feed fails the build.
Pass the generated updater without replacing the historical checkout updater.

Publish the new runtime ZIP, both unchanged native archives at their rebound
URLs, separately named dependency manifest/bootstrap, versioned installer feed,
Setup, build receipt, validation and installer checksums. Keep already published
app-only assets and root compatibility files unchanged. Future app-update
manifests must list supported older full-runtime identities and exact manifest
hashes. Test install/health, update/repeat, rejected update, rollback and generated
uninstall with preservation checks on the exact candidate before publication;
then verify anonymous download hashes and the public maintenance path before
promoting README. See [v1.1.1](releases/v1.1.1.md) for exact delivered identities.

## v1.1.0 application-only successor

The codec compatibility fix uses the unchanged v1.0.0 native runtime and the
existing installed updater. No new Setup executable or native archives are
produced. Download the v1.1.0 source and verify its hash against the immutable
release's `SHA256SUMS` and `package-provenance.json`. Its SHA-256 is
`cae9f307958319ad3175d3c7f6d0115c3b0faf8be9c8ae75e29c3c6ad47427db`.
Use the application commands below with `autoclip-1.1.0.tar.gz` and the
`autoclip-1.1.0` directory. The wheel must contain the built frontend and match
the source archive. Dependencies and original component notices remain unchanged.
See [the v1.1.0 record](releases/v1.1.0.md) for exact packaged identity and update
validation. The following v1.0.0 installer instructions remain applicable to
the unchanged installer/runtime, followed by the v1.1.0 application update ZIP.

## v1.0.0 runtime and installer

The application and installer have separate builds. The application source archive contains the editable backend and frontend. The installer compiles against the published runtime and native archives; it does not rebuild those dependencies.

## Application build

Use Windows x64, Python 3.11 or 3.12, Node.js 20+, and uv. Download [autoclip-1.0.0.tar.gz](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/autoclip-1.0.0.tar.gz). Its SHA-256 is `ed8482fbb5ac3652cdf9276cd5fad1aeceb65aed4eff6dc449899c2de0115c6a`.

From the folder containing the download, verify and extract it:

```powershell
$sourceArchive = Join-Path $PWD 'autoclip-1.0.0.tar.gz'
if ((Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash -ne 'ed8482fbb5ac3652cdf9276cd5fad1aeceb65aed4eff6dc449899c2de0115c6a') {
  throw 'Application source hash mismatch'
}
tar -xzf $sourceArchive
if ($LASTEXITCODE -ne 0) { throw 'Source extraction failed' }
Set-Location autoclip-1.0.0
uv venv --python 3.11
uv pip install -e '.[dev]'
Push-Location src/frontend
npm ci --include=dev
npm run build
Pop-Location
uv build --out-dir dist
```

The frontend build writes the static UI into `src/backend/autoclip/static`; build it before creating the wheel. Output is in `dist/`. For a local run, install a full FFmpeg CLI with `libass` and `libx264`, ensure `ffmpeg` and `ffprobe` are on PATH, then run `uv run --no-sync autoclip doctor` and `uv run --no-sync autoclip serve`.

This builds from the released application source using its declared Python dependencies and the frontend lockfile. It does not reproduce the complete pinned Windows runtime or guarantee byte-identical wheel output. Use the published runtime/native assets for the installer build below. The release source archive does not include the application's full test checkout.

## Installer inputs

Use Windows x64, Git, Python 3.11+, PowerShell, and the exact **Inno Setup 7.1.0 x64** compiler. Node.js and native build tools are not needed when compiling against the published archives.

Use installer source from tag `v1.0.0`, commit `b82a4bf50e5b621653dc9029e44c17fec4ecf937`. Download the six inputs below from [v1.0.0](https://github.com/Farkoal2128/AutoClip-MVP/releases/tag/v1.0.0). Keep them outside the Git checkout.

| Input | SHA-256 |
| --- | --- |
| `autoclip-windows-v1.0.0.zip` | `9dcb57506ab2246414e22dcc6ac664b7f4447ab6e04d22100b6dd5187fda037d` |
| `autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip` | `46ee07feb45b12e31c83fd49283f2053c729ca6f2073326b11a036d7c609f437` |
| `autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip` | `39f66da25a70447d241846de1a073a447aae7fd176ad4ce436ef0c53757dd678` |
| `installer-dependencies-v1.json` | `ec103faa541bf0e84d5f601e1afb4e8c2f460238001a65ec940b2c0070dc08c0` |
| `install.ps1` | `f49aa32e57f10d5528d35b0df7e1531bd76f5c52c09ed701f0b647b0f354d07d` |
| `update-app.ps1` | `dde9f456b52f1fb23a399c84373cb21c869bdea3e295600b0be8a627e2eaf7e8` |

Download the [Inno Setup compiler installer](https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-7.1.0-x64.exe) specified by the dependency manifest. Its SHA-256 is `0362a383ed217d4c4239b5933866dd96d3eb2102737da92f80f6057a4b40df2f`. Verify it before installing, then locate its `ISCC.exe`. The compiler executable must be **2,135,968 bytes**, SHA-256 `d06ebd38f38e3cee60a3c50cc45bd449d77e0bc6a5cabc607ea9886808e4de1a`. The build script enforces this identity.

## Compile the installer

Clone the release source into a new folder:

```powershell
git clone --branch v1.0.0 --single-branch https://github.com/Farkoal2128/AutoClip-MVP.git AutoClip-MVP-v1.0.0
Set-Location AutoClip-MVP-v1.0.0
$releaseInputs = Join-Path (Split-Path $PWD -Parent) 'release-inputs-v1.0.0'
New-Item -ItemType Directory -Path $releaseInputs -ErrorAction Stop | Out-Null
$releaseUrl = 'https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0'
$inputNames = @(
  'autoclip-windows-v1.0.0.zip'
  'autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip'
  'autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip'
  'installer-dependencies-v1.json'
  'install.ps1'
  'update-app.ps1'
)
foreach ($inputName in $inputNames) {
  Invoke-WebRequest -Uri "$releaseUrl/$inputName" -OutFile (Join-Path $releaseInputs $inputName) -ErrorAction Stop
}
Get-ChildItem -LiteralPath $releaseInputs -File | Get-FileHash -Algorithm SHA256
```

Compare **all six hashes** with the table before continuing. Confirm the checkout is at the commit above and its root `update-app.ps1` hash matches the downloaded file; the builder uses the updater from that tagged checkout. In the current checkout, the updater is `installer/update-app.ps1`, the dependency manifest is `release/installer-dependencies-v1.json`, and the build guide is `docs/BUILDING.md`. The v1.0.0 tag retains the original paths. The compiler also checks the runtime inventory, helper and notice inputs, and both native artifact graphs.

Set `$innoCompiler` to the installed compiler's actual path. From the release checkout, run:

```powershell
$innoCompiler = 'C:\Program Files\Inno Setup 7\ISCC.exe'
$candidateOutput = Join-Path (Split-Path $PWD -Parent) 'candidate-v1.0.0'
python scripts/build-inno.py `
  --manifest "$releaseInputs/installer-dependencies-v1.json" `
  --archive "$releaseInputs/autoclip-windows-v1.0.0.zip" `
  --bootstrap "$releaseInputs/install.ps1" `
  --iscc "$innoCompiler" `
  --native-artifact "$releaseInputs/autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip" `
  --nvidia-native-artifact "$releaseInputs/autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip" `
  --output-dir "$candidateOutput"
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
python -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) { throw 'Distribution checks failed' }
```

Use a new output directory. Outputs are `AutoClip-Setup-v1.exe` and `AutoClip-Setup-v1.receipt.json`; the executable includes installation and maintenance. CPU is the default, and NVIDIA remains selectable. Both native ZIPs are required for the unified installer. Do not use `--allow-local-candidate` for a distributable build.

Before publishing a new build, test install, healthy update, failed-update rejection, rollback, owned uninstall, and preservation of unrelated files on the exact executable. Retain the receipt, hashes, logs, and test results. A successful compilation does not establish lifecycle acceptance or third-party redistribution rights. Do not replace immutable v1.0.0 assets with a local rebuild; use a new release identity for changed payloads. See [distribution requirements](requirements/distribution.md) for successor packaging and [the v1.0.0 record](releases/v1.0.0.md) for completed verification.
