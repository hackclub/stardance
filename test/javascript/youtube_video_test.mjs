import test from "node:test";
import assert from "node:assert/strict";
import { YoutubeVideo } from "../../app/javascript/lib/youtube_video.js";

class FakePlayer {
  static last = null;
  state = 5;
  time = 0;
  seeks = [];
  playCalls = 0;
  muted = false;
  destroyed = false;

  constructor(mount, options) {
    FakePlayer.last = this;
    this.mount = mount;
    this.options = options;
    queueMicrotask(() => options.events.onReady());
  }

  getPlayerState() {
    return this.state;
  }
  getCurrentTime() {
    return this.time;
  }
  getDuration() {
    return 155;
  }
  seekTo(seconds) {
    this.seeks.push(seconds);
    this.time = seconds;
  }
  playVideo() {
    this.playCalls++;
    if (this.autoplays) this.setState(1);
  }
  pauseVideo() {
    this.setState(2);
  }
  mute() {
    this.muted = true;
  }
  unMute() {
    this.muted = false;
  }
  destroy() {
    this.destroyed = true;
  }
  setState(state) {
    this.state = state;
    this.options.events.onStateChange({ data: state });
  }
}

// The player is built once the IFrame API promise settles.
const settle = () => new Promise((resolve) => setImmediate(resolve));

function host(t) {
  const events = [];
  const element = {
    children: [],
    replaceChildren(...children) {
      this.children = children;
    },
    dispatchEvent(event) {
      events.push(event.type);
    },
  };
  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  globalThis.window = {
    YT: { Player: FakePlayer },
    location: { origin: "https://stardance.test" },
  };
  globalThis.document = { createElement: () => ({}) };
  t.after(() => {
    globalThis.window = originalWindow;
    globalThis.document = originalDocument;
  });
  return { element, events };
}

test("nothing is embedded until a video is loaded", (t) => {
  const { element } = host(t);
  const video = new YoutubeVideo(element);
  FakePlayer.last = null;
  assert.equal(video.readyState, 0);
  assert.equal(video.paused, true);
  assert.equal(FakePlayer.last, null);
  assert.deepEqual(element.children, []);
});

test("play joins the position set before the player started, unmuted", async (t) => {
  const { element, events } = host(t);
  const video = new YoutubeVideo(element);
  video.src = "QDDlOxdq-Ak";
  video.load();
  video.currentTime = 40;
  video.muted = false;
  await settle();
  const player = FakePlayer.last;
  assert.equal(player.options.videoId, "QDDlOxdq-Ak");
  assert.equal(player.options.playerVars.controls, 0);
  player.autoplays = true;
  await video.play();
  assert.deepEqual(player.seeks, [40], "cued videos only seek once playing");
  assert.equal(video.paused, false);
  assert.equal(video.readyState, 4);
  assert.equal(player.muted, false);
  assert.deepEqual(events, ["loadedmetadata", "canplay"]);
  player.time = 41;
  assert.equal(video.currentTime, 41);
  video.currentTime = 60;
  assert.deepEqual(player.seeks, [40, 60]);
});

test("a play request that never starts is reported as blocked autoplay", async (t) => {
  const { element } = host(t);
  let now = 0;
  t.mock.method(performance, "now", () => now);
  const video = new YoutubeVideo(element);
  video.src = "QDDlOxdq-Ak";
  video.load();
  video.currentTime = 12;
  const playing = video.play();
  await settle();
  now = 2000;
  await assert.rejects(playing, { name: "NotAllowedError" });
  assert.equal(video.paused, true);
  assert.equal(
    video.currentTime,
    12,
    "the requested position survives a retry",
  );
});

test("buffering keeps a play request alive and reports waiting", async (t) => {
  const { element, events } = host(t);
  let now = 0;
  t.mock.method(performance, "now", () => now);
  const video = new YoutubeVideo(element);
  video.src = "QDDlOxdq-Ak";
  video.load();
  await settle();
  const player = FakePlayer.last;
  const playing = video.play();
  player.setState(3);
  assert.equal(video.seeking, true);
  now = 1000;
  setTimeout(() => {
    now = 1400;
    player.setState(1);
  }, 150);
  await playing;
  assert.ok(events.includes("waiting"));
});

test("ending and errors surface as media events", async (t) => {
  const { element, events } = host(t);
  const video = new YoutubeVideo(element);
  video.src = "QDDlOxdq-Ak";
  video.load();
  await settle();
  const player = FakePlayer.last;
  player.setState(1);
  player.setState(0);
  assert.equal(video.paused, true);
  player.options.events.onError({ data: 150 });
  assert.deepEqual(events.slice(-3), ["canplay", "ended", "error"]);
});

test("clearing the source releases the player and aborts a pending play", async (t) => {
  const { element } = host(t);
  const video = new YoutubeVideo(element);
  video.src = "QDDlOxdq-Ak";
  video.load();
  await settle();
  const player = FakePlayer.last;
  const playing = video.play();
  video.pause();
  video.src = null;
  video.load();
  await assert.rejects(playing, { name: "AbortError" });
  assert.equal(player.destroyed, true);
  assert.deepEqual(element.children, []);
  assert.equal(video.readyState, 0);
  assert.equal(video.currentTime, 0);
  await assert.rejects(video.play(), { name: "AbortError" });
});
