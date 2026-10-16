# AutoClip — AI Video Clipper for Twitch, YouTube & Short-Form Content

**Open-source, local-first video clipping software for Windows.** Turn Twitch
VODs, YouTube videos, and local recordings into captioned highlights for
**YouTube Shorts, TikTok, Instagram Reels, and Facebook Reels**.

AutoClip transcribes your recording, uses AI to suggest highlight clips, lets
you review and edit them, and exports MP4 video. Streamers can repurpose past
broadcasts; podcasters, educators, and other creators can cut long-form videos
into short-form content. Run highlight selection locally with Ollama or choose
a supported cloud AI provider.

**[Download AutoClip for Windows](https://github.com/Farkoal2128/AutoClip-MVP/releases/latest)**
· [Creator guide](docs/CREATOR_GUIDE.md)
· [Platform support](#streaming-platforms-and-video-sources)
· [Questions and answers](#frequently-asked-questions)

## Make short clips from long videos

- **AI highlight detection:** find candidate moments in spoken content, then review the suggestions yourself.
- **Automatic captions:** transcribe with Whisper, edit captions, and burn styled subtitles into your clips; optional SRT subtitle files are available at export.
- **Vertical video editing:** export 9:16 clips, or choose 1:1 square and 16:9 landscape. Automatic reframing uses a centered crop; the manual Layout editor handles custom framing.
- **Local AI workflow:** use Whisper and Ollama for local processing without a paid AI API. Optional cloud providers receive transcript text for highlight selection.
- **Windows desktop app:** use the local browser interface with CPU processing or the optional NVIDIA installation profile.

## Streaming platforms and video sources

| Source | How to use it with AutoClip |
| --- | --- |
| Twitch VODs / past broadcasts | Paste a Twitch VOD URL such as `https://www.twitch.tv/videos/123456789`. Live channel pages and Twitch clip URLs are not accepted as direct sources. |
| YouTube videos / completed livestream replays | Paste a YouTube video URL. The recording must be available and downloadable; access restrictions can require your signed-in browser cookies. |
| Kick streams and clips | Import a compatible local recording or downloaded clip you have permission to use. Direct Kick URL import is not supported in v1.2.0. |
| Facebook Live, TikTok LIVE, Instagram Live, and other broadcasts | Import a compatible local recording. These services do not have direct URL integrations in v1.2.0. |
| OBS Studio / Streamlabs recordings | Import the saved video file, for example MP4, MKV, MOV, or WebM. Media must pass the app's validation. |
| Video podcasts, interviews, webinars, tutorials, and gaming recordings | Import your local video, or use a supported YouTube URL, to select and edit excerpts. |

AutoClip processes recorded media after the broadcast. It does not monitor
live channels or automatically capture a stream while you are live.

## Export for Shorts, Reels, TikTok, and other social video

Choose **9:16 vertical video** for a typical YouTube Shorts, Instagram Reels,
TikTok, or Facebook Reels workflow. Use square or landscape exports when those
better fit your composition. Other destinations, including Snapchat Spotlight,
X, and LinkedIn video, may also accept your exported file; check their current
upload requirements before posting.

You review the finished MP4 and upload it yourself. AutoClip does not include
direct social publishing, scheduling, or automatic cross-posting. Aspect ratio
alone does not guarantee that a destination will accept a file.

See the [creator guide](docs/CREATOR_GUIDE.md) for Twitch-to-TikTok,
YouTube-to-Shorts, Kick-recording, and podcast-clipping workflows.

## Frequently asked questions

### Is AutoClip free and open source?

AutoClip-authored code is MIT licensed. There is no AutoClip subscription or
export watermark. Local AI can run without paid API usage; optional cloud AI
services may charge their own fees. Third-party components retain their licenses.

### Can I turn a Twitch stream into YouTube Shorts or TikToks?

Yes: import the completed Twitch VOD, generate and review candidate highlights,
adjust the vertical layout and captions, then export and upload the clips.

### Can I use AutoClip as a Kick clip maker?

Use a compatible local Kick recording or downloaded clip you are authorized to
edit. AutoClip does not accept Kick URLs directly. The same local-file approach
applies to recordings from other streaming platforms.

### Does AutoClip upload my videos to an AI service?

Video and audio processing run locally. Cloud highlight providers receive
transcript text when selected. Choose Ollama for local highlight selection;
initial setup, model downloads, and remote video ingestion still need network access.

### Will AI find every great gaming moment or guarantee viral clips?

No. Highlight selection uses the transcript and can miss visual-only gameplay,
silent reactions, or other moments. Review the suggestions before exporting;
views and audience growth are not guaranteed.

This repository provides the Windows installer, updates, and maintenance
source. The released application source is available below.

## Download and install

**Latest Windows release: [v1.2.0 — safety and reliability fixes](https://github.com/Farkoal2128/AutoClip-MVP/releases/tag/v1.2.0).**
Fixes frontend file traversal, unsafe storage-move overlap, stale clip-caption
loads, export workspace collisions, queue setup failures and invalid provider
settings. The local server validates Host/Origin before side effects; frontend
regression tests now run in CI. Ingest and recovery share their media-format set.
Retains v1.1.1 native-resolution downloads and v1.1.0 video/audio codec fixes.
For a new installation, download [AutoClip-Setup-v1.2.0.exe](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.2.0/AutoClip-Setup-v1.2.0.exe).
Setup installs v1.2.0 directly; no separate update is needed. Existing v1.1.1,
v1.0.0/MVP installations use the [update ZIP](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.2.0/AutoClip-Update-v1.2.0.zip)
and instructions below. Original media and saved clips are preserved.
See the [v1.2.0 fixes and validation record](docs/releases/v1.2.0.md).

Twitch may require a signed-in session to expose 1440p source video. Select
your signed-in browser in Settings under **YouTube / Twitch cookies from**,
close that browser, and download again. Existing sources need a new download
to obtain better quality. Export canvas and encoder settings are unchanged.

The app wheel and frontend match the verified v1.2.0 update package. Existing
qualified CPU/NVIDIA components are reused without a native rebuild.

Run the installer and choose **Install AutoClip**. CPU is the default profile. The NVIDIA profile uses prebuilt native wheels and checks compatible GPU prerequisites. Review the prerequisite terms shown by Setup. **Launch AutoClip** on the final page opens the application.

For a v1.2.0 installation, run the same installer again to choose **Update AutoClip** or **Roll back the application**. Remove AutoClip through Windows Installed apps. Shared prerequisites, user data, and files not owned by the installation are preserved.

### Updating an existing MVP or draft installation

Download [AutoClip-Update-v1.2.0.zip](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.2.0/AutoClip-Update-v1.2.0.zip), finish or cancel current processing, quit AutoClip, and extract the ZIP. Follow its `UPDATE.md` to apply the 1.2.0 application with your installed updater. Supports exact v1.1.1, v1.0.0 and MVP r1 runtimes. This retains the verified runtime, installed maintenance files and previous application for rollback. Installed updaters pin older feed bytes: use the ZIP's explicit local manifest/wheel inputs. The root feed remains at v1.0.0 for compatibility. The new Setup refuses a different existing runtime before writing files; use the update ZIP for older installations. A new v1.2.0 installation is already current.

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

The latest [AutoClip v1.2.0 application source](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.2.0/autoclip-1.2.0.tar.gz)
is a clean archive of [application commit 9054f336](https://github.com/Farkoal2128/myAutoclip/commit/9054f336f70f3b352e766ebcf1db1f792759dadb).
It includes the backend, editable frontend, bundled UI, dependency manifests,
contracts, tests and license. `package-provenance.json`, `SHA256SUMS` and the
Setup build receipt identify the delivered source, wheel and installer. All
packaged application source members match that archive. Qualified CPU/NVIDIA
components retain their existing bytes and notices.

Download the [AutoClip v1.0.0 application source](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/autoclip-1.0.0.tar.gz). It includes the Python backend, editable React/TypeScript frontend, dependency manifests, and MIT license. Installer source is in this repository; the [v1.0.0 tag](https://github.com/Farkoal2128/AutoClip-MVP/tree/v1.0.0) contains the source used for the published installer.

## Build and verification

See [the build guide](docs/BUILDING.md) for exact inputs, current Windows build commands and the required matching installer for every future public update, and [distribution requirements](docs/requirements/distribution.md) for release rules. Installer builds require Windows, Python 3.11+, and the exact Inno Setup compiler recorded in the dependency manifest. A build receipt identifies the executable and every bundled helper. Local candidate builds do not establish publication readiness.

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
