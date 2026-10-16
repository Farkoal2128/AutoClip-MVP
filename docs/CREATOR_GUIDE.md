# AutoClip Creator Guide: Livestream Highlights and Short-Form Video

[AutoClip](../README.md) is an open-source AI video clipper for Windows. This
guide covers turning recorded streams and long videos into reviewed,
captioned clips for social media. Platform support here describes v1.2.0.

## Start with a recording

1. [Download the Windows installer](https://github.com/Farkoal2128/AutoClip-MVP/releases/latest) and follow the [installation instructions](../README.md#download-and-install).
2. Choose a highlight provider in Settings. Ollama provides local AI; supported cloud providers require their own configuration and may incur charges.
3. Add a supported YouTube video URL, a completed Twitch VOD URL, or a local media file.
4. Transcribe the source and generate suggested highlights. Speech recognition and AI suggestions can be wrong, so listen and review each candidate.
5. Adjust cuts, correct captions, and choose the framing in Review and Layout.
6. Export an MP4, inspect the result, and upload it to your chosen destination.

The Windows installer is the simplest entry point. Developer builds and
application source downloads are documented in the [repository README](../README.md#source-code).

## Twitch VOD to TikTok, Instagram Reels, or YouTube Shorts

Paste a past-broadcast URL, for example `https://www.twitch.tv/videos/123456789`.
AutoClip needs a finite recording; a live channel URL is not a supported source.
For an existing Twitch clip, import a compatible downloaded file instead of its
clip URL.

Generate candidate highlights, then choose **9:16** for a vertical composition.
Automatic reframing uses a centered crop. Use Layout to position the relevant
source regions when your facecam, gameplay, or interview subject needs different
framing. Check that captions are readable and that the beginning and end of the
clip preserve the speaker's meaning.

If a download needs authentication or a higher-quality source format, select
your signed-in browser under **YouTube / Twitch cookies from** in Settings and
close that browser before downloading. Your account must have access to the
recording. A fresh download is needed to obtain a better source; an export
setting cannot recover detail missing from the input.

## YouTube video or livestream replay to Shorts

Use a recorded YouTube video or an available, completed livestream replay.
Choose a self-contained explanation, reaction, tutorial step, or interview
answer, then review the proposed cut and captions before exporting.

YouTube's [Shorts eligibility rules](https://support.google.com/youtube/answer/15424877?hl=en)
cover duration, orientation, upload date, and some channel-specific cases.
Select a suitable duration and layout rather than assuming every MP4 will be
classified as a Short. Upload through YouTube yourself; AutoClip does not
connect a channel or publish on your behalf.

## Kick and other livestream recordings

**Direct Kick URL import is not supported.** Import your own local stream
recording or a compatible downloaded clip you have permission to reuse.
KICK's [clip guide](https://help.kick.com/en/articles/7120566-how-to-create-clips-on-kick)
explains its native clip workflow. AutoClip edits the resulting local media;
it does not create native KICK clips through an integration.

The same approach works for compatible recordings from Facebook Live, TikTok
LIVE, Instagram Live, and other streaming services, or files saved with OBS
Studio or Streamlabs. MP4, MKV, MOV, and WebM are examples of accepted video
containers; the app still validates the actual media. Naming a service here
describes a local-recording workflow, not a tested connection to that service.

## Podcast clips, interviews, webinars, and educational content

For video podcasts and talking-head content, choose a question and answer or
one complete point, rather than cutting a sentence away from the context that
makes it understandable. Local video import and supported YouTube URLs share
the same transcription, highlight review, caption, and export workflow.

Tutorials, lectures, product demos, and recorded webinars can also supply short
excerpts. AI highlight selection is based on speech transcripts; it is not a
game-event detector and may overlook action with no spoken explanation.

## Pick the destination after reviewing the clip

| Destination | Suggested starting point | Publishing |
| --- | --- | --- |
| YouTube Shorts | 9:16; check YouTube's current Shorts eligibility rules | Upload the exported file yourself |
| TikTok | 9:16; check duration and preview the caption placement | Upload the exported file yourself |
| Instagram Reels | 9:16; preview the cover and text placement in Instagram | Upload the exported file yourself |
| Facebook Reels | Start with a composition that fits the clip; check the current Facebook upload flow | Upload the exported file yourself |
| Snapchat Spotlight, X, LinkedIn video, and other destinations | Choose 9:16, 1:1, or 16:9 as appropriate; check that service's current file requirements | No dedicated integration; acceptance has not been tested here |

These are editing starting points, not certified platform presets. Each
service controls file acceptance, duration, music, captions, and availability.
Keep important text away from the destination's interface controls and inspect
the upload preview. Burned-in captions appear in the video; optional SRT files
are separate subtitle files, and each destination decides whether to accept them.

AutoClip has no direct uploading, social scheduler, automatic cross-posting,
real-time stream capture, or promised viral performance. Use recordings and
music you are authorized to publish.

[Back to AutoClip downloads, platform support, and source code](../README.md)
