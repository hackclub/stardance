# Finale playback

The live finale uses the server clock: November 1, 2026 at 12:35 PM Eastern
(17:35 UTC). Shipping still closes at noon Eastern; the October 31 event and
time-logging cutoffs are unchanged.
The video/audio starts immediately with 8 seconds of disintegration and
2 seconds fading to black. Its first 10 seconds play underneath the page;
at 12:35:10 PM EST the picture is revealed without restarting the video.
A visitor joining 40 seconds after the finale starts joins 40 seconds into the video.
Buffering and returning from a background
tab catch up to that same timeline. This is scheduled playback of a YouTube
video; no livestream or Rails video proxy is needed.

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
everyone, including signed-out visitors. A YouTube video must be configured. Open pages pick up flag changes on their next server-clock sync
(at most about 30 seconds); refresh for an immediate check.

This starts a private replay from the beginning, restores the site afterward,
and does not move the countdown or mark the live finale as watched. Turning
the flag off prevents new early replays without interrupting one already in
progress. After the live window, replay remains available automatically even
with the flag off, so it can also be left enabled after the event.

## Supplying the finished video

The finale plays from YouTube. Set the video ID and its runtime in seconds in
`config/initializers/constants.rb` (`stardance_finale_youtube_id` and
`stardance_finale_video_duration_seconds`), then deploy; update both together,
since the runtime bounds the shared live window. The video must be public or
unlisted with embedding allowed. The first 10 seconds play under
destruction/fade. Clips shorter than that still allow the visual sequence to finish.

Open pages receive the video ID and duration through `/server_time` on their next
30-second sync. Without a video ID or a positive duration, the destruction/fade ends
after 10 seconds, restores the site, and does not offer a broken replay.

## Loading and playback

- No YouTube embed or media requests on ordinary page loads or post-event visits.
- Embed the player only within 30 seconds of the live event (skip speculative
  loading when the browser reports Data Saver), or when replay is selected.
- `app/javascript/lib/youtube_video.js` wraps the YouTube IFrame API
  (privacy-enhanced `youtube-nocookie.com` embed, YouTube's own controls hidden)
  behind the small media-element interface the finale controller uses. A play
  request that doesn't start within 1.5 seconds (outside buffering) counts as
  blocked autoplay.
- Correct live drift over one second, with seeks limited to avoid repeatedly
  restarting a slow seek. Network speeds still affect what a viewer can see;
  playback is synchronized approximately, not frame-exact.
- Try sound first; fall back to muted autoplay with a **turn sound on** button
  that remains available even during disintegration and fading.
  If autoplay is blocked entirely, **play finale** joins the current moment.
- Pause media in hidden tabs and the disintegration renderer behind the video.
  Remove the YouTube player on exit or navigation.
- Errors and blocked autoplay never trap someone: they can return to the site,
  and the live window ends even if the video fails to load.

Replays also start audio with disintegration, then reveal the already-playing
video at the end of the fade. The local simulator still previews the full sequence and supports its existing
destruction duration override. Public replay always uses 8 seconds plus the
2-second fade. Neither path changes user settings or saves dismissal records.
