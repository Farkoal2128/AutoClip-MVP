# AutoClip MVP distribution

All future AutoClip installer and application distributions use
`https://github.com/Farkoal2128/AutoClip-MVP`. Operational release downloads,
app update discovery and app-wheel allowlists must use this repository and
must not fall back to `Farkoal2128/autoclip-runtime`.

This repository contains the minimum installer compiler, publisher producer,
validator and installed maintenance closure. Release packages, native archives
and executables belong in immutable GitHub releases, outside source control.
Original third-party notices and AutoClip MIT attribution remain intact.

Migrating a prepared package assigns a new immutable release identity and
rebinds its operative native-artifact URLs to the new repository. Native
runtime identities, artifact filenames, byte counts, hashes, qualification
receipts, application wheel bytes and historical evidence remain unchanged.
The operative distribution inventory and release file index must match the
resulting package. Regenerate exact outer manifest and standalone pins.
Reject input pin mismatches, unsafe release identities and existing outputs.

All original trust, consent, staging, activation, rollback, owned uninstall,
SHA-256 and byte verification remain required. A local migration does not
qualify an artifact or authorize publication. Publish and verify immutable
public assets before promoting public defaults. Final host lifecycle tests
are required before publication; no VM testing is claimed.

Until immutable assets are published and verified, the source bootstrap must
fail clearly instead of exposing a working default pinned to a missing asset.
After promotion, the bootstrap and app updater must match the delivered
dependency and app manifests. Installer builds use the separately generated,
pinned bootstrap during this staging period.

For the 2026-10-03 MVP prerelease, the owner explicitly selected exact package
review and local installation lifecycle tests as the acceptance criteria.
Historical V11/r22 external review gates retain their original scope.

Prerequisite detection must report absent or malfunctioning capabilities even
when a native probe writes to stderr or raises an error. Failed probes do not
prove capability availability: downloadable prerequisites remain missing, and
missing system-provided prerequisites continue to block installation. Such probe
failures must not prevent the prerequisite report from being written.

## Maintainer build

Keep exact archives/manifests and candidate output outside the Git checkout.
Generate a successor from the currently published release inputs with
`scripts/build-publisher-cpu-release.py`, supplying separately qualified CPU
and NVIDIA component receipts. Use `scripts/rebind-distribution.py --help`
for the pinned destination migration arguments. It emits the runtime ZIP,
dependency manifest, bootstrap, app feed and matching app updater.

Copy the generated `update-app.ps1` into the checkout before compiling. Pass
the generated bootstrap explicitly; do not use the pending source default.
With the exact local files named below, compile with:

```powershell
python scripts/build-inno.py `
  --manifest ../release-inputs/installer-dependencies-v1.json `
  --archive ../release-inputs/autoclip-mvp-v0.1.0-20261003-r1.zip `
  --bootstrap ../release-inputs/install.ps1 `
  --iscc ../inno/ISCC.exe `
  --native-artifact ../release-inputs/autoclip-cpu-native-win_x64-cp311-v1-20261002-3343baed-r2.zip `
  --nvidia-native-artifact ../release-inputs/autoclip-nvidia-native-win_x64-cp311-20261003-r2.zip `
  --output-dir ../candidate
python -m unittest discover -s tests -v
```

The compiler must match the manifest's pinned executable hash. The output
directory must be new. Default compilation verifies both profile graphs and
component qualification; do not publish a local-candidate opt-in build.
Run the complete host lifecycle on this exact executable before release.
Publish and verify the immutable assets, then promote the generated bootstrap,
app feed and dependency manifest to the default branch. Preserve the generated
updater pin, build receipt and final validation record.
