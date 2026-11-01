export const DISINTEGRATION_MS = 8000;
export const FADE_MS = 2000;
export const COUNTDOWN_MS = 3000;
export const REPLAY_COUNTDOWN_MS = 12000;

// A scheduled broadcast of a static file, not a stream through the Rails app.
export function finaleTimeline(sample) {
  const startsAt = Date.parse(sample?.ends_at);
  if (!Number.isFinite(startsAt)) return null;
  const duration = Number(sample?.finale?.duration_seconds);
  const url = sample?.finale?.video_url;
  const ready = !!url && Number.isFinite(duration) && duration > 0;
  const revealAt = startsAt + DISINTEGRATION_MS + FADE_MS;
  return {
    startsAt,
    revealAt,
    // The first ten seconds of the file play under the destruction and fade.
    finishesAt: Math.max(revealAt, startsAt + (ready ? duration * 1000 : 0)),
    url: ready ? url : null,
    ready,
    onDemand: sample?.finale?.on_demand === true,
  };
}

export function canReplayFinale(timeline, now) {
  return !!(
    timeline?.ready &&
    Number.isFinite(now) &&
    (timeline.onDemand || now >= timeline.finishesAt)
  );
}
