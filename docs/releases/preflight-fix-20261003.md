# Preflight fix candidate, 2026-10-03

This historical record is superseded by [v1.0.0](v1.0.0.md). The owner requested removal of its draft/prerelease entry after verified consolidation; retained release assets and notices are listed in the v1.0.0 validation packet.

The second-PC log identifies a stale Scoop FFmpeg shim whose target executable
is missing. Windows PowerShell 5.1 promoted its redirected stderr to a terminating
NativeCommandError, preventing the prerequisite report from being written.
Capability probes now classify exceptions as failed capability checks. Missing
downloadable tools can proceed to pinned acquisition; system-provided missing
prerequisites remain blocked. Normal successful preflight exits explicitly with 0.
No dependency trust or consent rules changed; no HTTP/API contract changed.

RED: the broken FFmpeg and NVIDIA subprocess cases both failed before producing
a report. GREEN: `python -m unittest discover -s tests -p test_preflight.py -v`
passed 3 cases; `python -m unittest discover -s tests -v` passed all 8 cases.
PowerShell parsing passed. The real pinned Inno compiler built successfully with
strict CPU/NVIDIA component validation, without local-candidate opt-in.

The rebuilt setup hash is `633bc76becc95d33b7cb6ec9f0f03d6d5a3d5c76468d3bae1583831ed28aae58`.
It reuses the published r1 app/runtime/native assets. Build receipt comparison
changed only the preflight helper hash, setup/maintenance executable hashes and
sizes, and the equivalent bootstrap's local input path. All other helper and
artifact pins match the original tested build.

The owner reported on 2026-10-03 that installation on the other machine completed
successfully. This is user-reported acceptance; its executable hash and profile
were not independently supplied or verified. Complete native lifecycle acceptance
was not rerun on this executable; the prior public release's lifecycle record
remains scoped to its original binary. This release remains a draft. The later
Settings yt-dlp update button is packaged in a separate app-only owner-test draft;
it is not present in this candidate's unchanged r1 application payload. See the
[app update test instructions](v0.1.0-mvp-20261003-ytdlp-update1.md).

The owner cancelled publisher signing because of its cost. No security protections
were disabled. No VM or Computer Use occurred during this follow-up.
