# Finale playback

The live finale uses the server clock: November 1, 2026 at 12:15 PM Eastern
(17:15 UTC). Shipping still closes at noon Eastern; the October 31 event and
time-logging cutoffs are unchanged.
The video/audio starts immediately with 8 seconds of disintegration and
2 seconds fading to black. Its first 10 seconds play underneath the page;
at 12:15:10 PM EST the picture is revealed without restarting the file.
A visitor joining 40 seconds after the finale starts joins 40 seconds into the video.
Buffering and returning from a background
tab catch up to that same timeline. This is scheduled playback of a static
file; no livestream server or Rails video proxy is needed.

After the scheduled video runtime, the page restores its normal pre-finale
damage and preferences. Refreshes and future visits never automatically replay
the event. The clock remains at zero and offers **replay the finale**, which
replays the full sequence independently with normal video controls. The
countdown visibility preference still applies. Admin pages remain excluded.

### Production review with Flipper

Enable **`finaleondemand`** to show **replay the finale** before the live
countdown ends. It is registered disabled by default. Enable it for just your
user (an actor in Flipper) to review on production, or globally to offer it to
everyone, including signed-out visitors. The video URL and runtime must be
configured. Open pages pick up flag changes on their next server-clock sync
(at most about 30 seconds); refresh for an immediate check.

This starts a private replay from the beginning, restores the site afterward,
and does not move the countdown or mark the live finale as watched. Turning
the flag off prevents new early replays without interrupting one already in
progress. After the live window, replay remains available automatically even
with the flag off, so it can also be left enabled after the event.

## Supplying the finished video

Set these on the deployed application and restart it:

```text
STARDANCE_FINALE_VIDEO_URL=https://your-asset-host.example/finale-v1.mp4
STARDANCE_FINALE_VIDEO_DURATION_SECONDS=123.456
```

The runtime above is an example: use the exact duration of the entire final
file, including its first 10 seconds of audio over the destruction/fade.
Do not add 10 seconds to the runtime. Clips shorter than the destruction/fade
still allow that sequence to finish before restoring the page.
An MP3 contains audio only; use an MP4 containing video and audio. An existing
asset host/CDN is preferred. A file at `public/videos/finale-v1.mp4` also works
with the URL `/videos/finale-v1.mp4`, if the production static file server
serves byte ranges. A relative URL means public assets, not an asset pipeline
logical filename. Do not put the file inside the JavaScript bundle.

Use H.264 video/AAC audio, a sensible resolution/bitrate (720p is a useful
starting point), and MP4 fast-start metadata. The host should send
`Content-Type: video/mp4`, support byte ranges (`206 Partial Content`), and
cache an immutable, versioned URL. Check seeking at a late timestamp before
launch. Use the same file/runtime on every server; changing runtime during the
event changes the shared end time.

The URL and runtime are read from `/server_time` every 30 seconds, so pages
already open receive configuration updates without reloading. Configure both
before the event. If either is missing or invalid, the destruction/fade still
ends after 10 seconds, restores the site, and does not offer a broken replay.

## Loading and playback

- No video `src` or media requests on ordinary page loads or post-event visits.
- Start buffering only within 30 seconds of the live event (skip speculative
  buffering when the browser reports Data Saver), or when replay is selected.
- Native video decoding; no additional player library or whole-file JS fetch.
- Correct live drift over one second, with seeks limited to avoid repeatedly
  restarting a slow seek. Network speeds still affect what a viewer can see;
  playback is synchronized approximately, not frame-exact.
- Try sound first; fall back to muted autoplay with a **turn sound on** button
  that remains available even during disintegration and fading.
  If autoplay is blocked entirely, **play finale** joins the current moment.
- Pause media in hidden tabs and the disintegration renderer behind the video.
  Release the media source/buffers on exit or navigation.
- Errors and blocked autoplay never trap someone: they can return to the site,
  and the live window ends even if the file fails to load.

Replays also start audio with disintegration, then reveal the already-playing
video at the end of the fade. The local simulator still previews the full sequence and supports its existing
destruction duration override. Public replay always uses 8 seconds plus the
2-second fade. Neither path changes user settings or saves dismissal records.
