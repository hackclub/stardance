# Finale playback

The live finale uses the server clock: November 1, 2026 at 12:35 PM Eastern
(17:35 UTC). Shipping still closes at noon Eastern; the October 31 event and
time-logging cutoffs are unchanged.
The video/audio starts immediately with 8 seconds of disintegration and
2 seconds fading to black. Its first 10 seconds play underneath the page;
at 12:35:10 PM EST the picture is revealed without restarting the file.
A visitor joining 40 seconds after the finale starts joins 40 seconds into the video.
Buffering and returning from a background
tab catch up to that same timeline. This is scheduled playback of a static
file; no livestream server or Rails video proxy is needed.

After the scheduled video runtime, the page restores its normal pre-finale
damage and preferences. After the live window, each viewer's first click/tap or Enter/Space interaction
starts a full catch-up replay with a 12-second countdown. This is offered once:
signed-in viewers are recorded through the existing account dismissals endpoint,
and guests are remembered in browser storage. The marker is saved when the
sequence starts, so exiting or navigating away does not repeatedly interrupt them.
Browser storage also guards against repeats before the account save completes.
If browser storage is unavailable, guests are remembered only for the current page.
Existing intro dialogs finish first; admin pages remain excluded. The clock remains at zero and offers **replay the finale**, which
starts a fresh 12-second countdown, then replays the full sequence independently
without native video controls or a return button. The page restores automatically
when playback ends; Escape can also exit the sequence. The
countdown visibility preference still applies. Admin pages remain excluded.

### Production review with Flipper

Enable **`finaleondemand`** to show **replay the finale** before the live
countdown ends. It is registered disabled by default. Enable it for just your
user (an actor in Flipper) to review on production, or globally to offer it to
everyone, including signed-out visitors. The video file must be included in the deployment. Open pages pick up flag changes on their next server-clock sync
(at most about 30 seconds); refresh for an immediate check.

This starts a private replay from the beginning, restores the site afterward,
and does not move the countdown or mark the live finale as watched. Turning
the flag off prevents new early replays without interrupting one already in
progress. After the live window, replay remains available automatically even
with the flag off, so it can also be left enabled after the event.

## Supplying the finished video

Put the finished MP4 at **`public/videos/finale.mp4`**, commit it, and deploy.
No environment variables or manual duration settings are needed. The application
reads its full runtime once at boot using ffprobe (already included in both Docker
images). The first 10 seconds of the file play under destruction/fade.
Clips shorter than that still allow the visual sequence to finish.

Use H.264 video/AAC audio and MP4 fast-start metadata. The file is served directly
as `/videos/finale.mp4`, outside the JavaScript bundle; the published URL includes
a file version to avoid reusing an older cached clip. The static server must
support byte ranges for late-arrival seeking. Deploy the same file to every server.

Open pages receive the URL and duration through `/server_time` on their next
30-second sync. If the file is missing or unreadable, the destruction/fade ends
after 10 seconds, restores the site, and does not offer a broken replay.

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
