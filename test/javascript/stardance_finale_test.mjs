import test from "node:test";
import assert from "node:assert/strict";
import { serverClock } from "../../app/javascript/lib/server_clock.js";
import { finaleTimeline } from "../../app/javascript/lib/stardance_finale_timeline.js";
import FinaleController from "../../app/javascript/controllers/stardance_finale_controller.js";

const start = Date.parse("2026-11-01T17:00:00Z");
const sample = () => ({
  ends_at: new Date(start).toISOString(),
  ended: true,
  finale: { video_url: "/videos/finale.mp4", duration_seconds: 120 },
});

function browser(t) {
  const stored = new Map();
  const storage = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem: (key) => stored.get(key),
      setItem: (key, value) => stored.set(key, value),
    },
  });
  t.after(() => {
    if (storage) Object.defineProperty(globalThis, "localStorage", storage);
    else delete globalThis.localStorage;
  });
  const data = serverClock.data;
  serverClock.data = sample();
  t.after(() => {
    serverClock.data = data;
  });
  t.mock.method(serverClock, "now", () => start);
  t.mock.method(performance, "now", () => 1000);
  const originalDocument = globalThis.document;
  globalThis.document = {
    hidden: false,
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener() {},
    removeEventListener() {},
  };
  t.after(() => {
    globalThis.document = originalDocument;
  });
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "navigator");
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {},
  });
  t.after(() => {
    if (descriptor) Object.defineProperty(globalThis, "navigator", descriptor);
    else delete globalThis.navigator;
  });
  return (offset) => {
    serverClock.now.mock.mockImplementation(() => start + offset);
    return start + offset;
  };
}

function controller(overrides = {}) {
  const c = {
    phase: "idle",
    generation: 0,
    endsAtValue: new Date(start).toISOString(),
    previewEnabledValue: false,
    events: [],
    dialogTarget: {
      open: false,
      showModal() {
        this.open = true;
      },
      close() {
        this.open = false;
      },
    },
    panelTarget: { hidden: true, classList: { add() {}, remove() {} } },
    statusTarget: {},
    previewResetTarget: {},
    playTarget: {},
    videoTarget: {
      paused: true,
      readyState: 1,
      duration: 120,
      currentTime: 0,
      loadCalls: 0,
      playCalls: 0,
      hasAttribute(name) {
        return !!this[name];
      },
      getAttribute(name) {
        return this[name] || null;
      },
      removeAttribute(name) {
        delete this[name];
      },
      load() {
        this.loadCalls++;
      },
      pause() {
        this.paused = true;
      },
      async play() {
        this.playCalls++;
        this.paused = false;
      },
    },
    fadeTarget: {
      animate(frames, options) {
        this.frames = frames;
        this.options = options;
        const animation = {
          finished: new Promise((resolve, reject) => {
            this.resolve = resolve;
            this.reject = reject;
          }),
          cancel: () => this.reject(new Error("cancelled")),
        };
        return animation;
      },
    },
    dispatch(name, options) {
      this.events.push({ name, ...options });
    },
  };
  for (const name of Object.getOwnPropertyNames(FinaleController.prototype)) {
    if (name !== "constructor")
      c[name] = FinaleController.prototype[name].bind(c);
  }
  return Object.assign(c, overrides);
}

test("new viewers join the current video position instead of repeating destruction", async (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(at(40000));
  await Promise.resolve();
  assert.equal(c.phase, "video");
  assert.equal(c.videoTarget.currentTime, 40);
  assert.equal(c.videoTarget.controls, false);
  assert.equal(c.videoTarget.paused, false);
  assert.deepEqual(
    c.events.map((e) => e.name),
    ["video"],
  );
});

test("live arrivals during destruction start at elapsed progress and fade only for the remaining time", (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(at(4000));
  assert.equal(c.phase, "disintegrating");
  assert.equal(c.videoTarget.currentTime, 4);
  assert.equal(
    c.videoTarget.paused,
    false,
    "audio already plays during destruction",
  );
  assert.deepEqual(c.events[0], {
    name: "disintegrate",
    detail: { elapsedMs: 4000, durationMs: 8000 },
  });
  c.fadeToBlack();
  assert.equal(
    c.phase,
    "disintegrating",
    "a fast renderer cannot advance the live broadcast",
  );
  c.tick(at(9000));
  assert.equal(c.phase, "fading");
  assert.equal(c.fadeTarget.options.duration, 1000);
  assert.deepEqual(c.fadeTarget.frames, [{ opacity: 0.5 }, { opacity: 1 }]);
  c.tick(at(10000));
  assert.equal(c.phase, "video");
  assert.equal(
    c.videoTarget.currentTime,
    10,
    "revealing the picture must not restart playback",
  );
});

test("media starts at countdown zero and stays underneath the full destruction and fade", async (t) => {
  const at = browser(t);
  const c = controller();
  const classes = new Set();
  c.panelTarget.classList = {
    add: (name) => classes.add(name),
    remove: (name) => classes.delete(name),
  };
  c.tick(at(-3000));
  assert.equal(c.videoTarget.playCalls, 0);
  c.tick(at(0));
  await Promise.resolve();
  assert.equal(c.phase, "disintegrating");
  assert.equal(
    c.panelTarget.hidden,
    false,
    "sound controls are available immediately",
  );
  assert.equal(classes.has("stardance-finale__panel--intro"), true);
  assert.equal(c.videoTarget.currentTime, 0);
  assert.equal(c.videoTarget.paused, false);
  c.videoTarget.currentTime = 8;
  c.tick(at(8000));
  assert.equal(c.phase, "fading");
  assert.equal(classes.has("stardance-finale__panel--intro"), true);
  c.videoTarget.currentTime = 10;
  c.tick(at(10000));
  assert.equal(c.phase, "video");
  assert.equal(classes.has("stardance-finale__panel--intro"), false);
  assert.equal(c.videoTarget.currentTime, 10);
  assert.equal(
    c.videoTarget.loadCalls,
    1,
    "the same media element/source continues through the transition",
  );
});

test("replay begins audio with destruction and preserves its position when the fade ends", async (t) => {
  const at = browser(t);
  const c = controller();
  at(140000);
  c.replay();
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  await Promise.resolve();
  assert.equal(c.phase, "disintegrating");
  assert.equal(c.videoTarget.currentTime, 0);
  assert.equal(c.videoTarget.paused, false);
  performance.now.mock.mockImplementation(() => 21000);
  c.videoTarget.currentTime = 8;
  const fading = c.beginFade(2000);
  performance.now.mock.mockImplementation(() => 23000);
  c.videoTarget.currentTime = 10;
  c.fadeTarget.resolve();
  await fading;
  assert.equal(c.phase, "video");
  assert.equal(c.videoTarget.currentTime, 10);
});

test("late replay metadata catches up to the intro even after the picture is revealed", (t) => {
  const at = browser(t);
  const c = controller();
  at(140000);
  c.videoTarget.readyState = 0;
  c.replay();
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  performance.now.mock.mockImplementation(() => 25000);
  c.showVideo();
  c.videoTarget.readyState = 1;
  c.videoReady();
  assert.equal(c.videoTarget.currentTime, 12);
});

test("autoplay blocked during destruction offers sound immediately without exposing the picture", async (t) => {
  const at = browser(t);
  const c = controller();
  c.videoTarget.play = async function () {
    if (!this.muted) throw new DOMException("blocked", "NotAllowedError");
    this.paused = false;
  };
  c.tick(at(0));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(c.phase, "disintegrating");
  assert.equal(c.panelTarget.hidden, false);
  assert.equal(c.playTarget.hidden, false);
  assert.equal(c.playTarget.textContent, "turn sound on");
  c.videoTarget.play = async function () {
    this.paused = false;
  };
  at(4000);
  c.playVideo();
  assert.equal(c.videoTarget.muted, false);
  assert.equal(c.videoTarget.currentTime, 4);
  assert.equal(c.phase, "disintegrating");
});

test("a short file cannot cut off destruction or the fade", (t) => {
  const at = browser(t);
  serverClock.data.finale.duration_seconds = 5;
  assert.equal(finaleTimeline(serverClock.data).finishesAt, start + 10000);
  const c = controller();
  c.tick(at(0));
  at(5000);
  c.videoEnded();
  assert.equal(c.phase, "disintegrating");
  c.tick(at(9000));
  assert.equal(c.phase, "fading");
  c.tick(at(10000));
  assert.equal(c.phase, "idle");
});

test("initial visits during the fade catch up without a fresh eight-second animation", (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(at(9500));
  assert.equal(c.phase, "fading");
  assert.equal(c.events[0].detail.elapsedMs, 8000);
  assert.equal(c.fadeTarget.options.duration, 500);
});

test("the live event restores the page at its end, including a stalled video, and later visits do nothing", (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(at(20000));
  c.mediaFailed = true;
  c.tick(at(120000));
  assert.equal(c.phase, "idle");
  assert.equal(c.dialogTarget.open, false);
  assert.equal(c.videoTarget.hasAttribute("src"), false);
  assert.equal(c.events.at(-1).name, "reset");
  c.tick(at(140000));
  assert.equal(c.phase, "idle");
  const fresh = controller();
  fresh.tick(at(86400000));
  assert.equal(fresh.phase, "idle");
  assert.equal(fresh.videoTarget.loadCalls, 0);
});

test("metadata and buffering delays seek to the current shared time, not the arrival time", (t) => {
  const at = browser(t);
  const c = controller();
  c.videoTarget.readyState = 0;
  c.tick(at(30000));
  assert.equal(c.videoTarget.currentTime, 0);
  c.videoTarget.readyState = 1;
  at(60000);
  c.videoReady();
  assert.equal(c.videoTarget.currentTime, 60);
  c.videoTarget.currentTime = 51;
  performance.now.mock.mockImplementation(() => 5000);
  c.tick(at(80000));
  assert.equal(c.videoTarget.currentTime, 80);
  c.videoTarget.seeking = true;
  c.tick(at(90000));
  assert.equal(
    c.videoTarget.currentTime,
    80,
    "do not restart an ongoing slow seek on every tick",
  );
});

test("background tabs pause and join the current live moment after server clock resynchronization", (t) => {
  const at = browser(t);
  t.mock.method(serverClock, "subscribe", () => () => {});
  t.mock.method(globalThis, "setInterval", () => 1);
  const c = controller();
  at(-60000);
  c.connect();
  c.tick(at(20000));
  document.hidden = true;
  c.visibility();
  assert.equal(c.videoTarget.paused, true);
  c.tick(at(50000));
  assert.equal(c.videoTarget.currentTime, 20);
  document.hidden = false;
  performance.now.mock.mockImplementation(() => 10000);
  c.tick(at(70000));
  assert.equal(c.videoTarget.currentTime, 70);
  c.tick(at(200000));
  assert.equal(c.phase, "idle");
});

test("ordinary visits never fetch the video; near-start warmup respects Data Saver", (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(at(-60000));
  assert.equal(c.videoTarget.loadCalls, 0);
  navigator.connection = { saveData: true };
  c.tick(at(-15000));
  assert.equal(c.videoTarget.loadCalls, 0);
  navigator.connection.saveData = false;
  c.tick(at(-15000));
  c.tick(at(-5000));
  assert.equal(c.videoTarget.loadCalls, 1);
  assert.equal(c.videoTarget.preload, "auto");
  assert.equal(c.videoTarget.playCalls, 0);
});

test("the October 31 deadline does not start a finale, and the explosion requires server confirmation", async (t) => {
  const at = browser(t);
  const c = controller();
  c.tick(Date.parse("2026-11-01T00:00:00-04:00"));
  assert.equal(c.phase, "idle");
  serverClock.data.ended = false;
  t.mock.method(serverClock, "sync", async () => null);
  c.tick(at(0));
  await Promise.resolve();
  assert.deepEqual(c.events, []);
  serverClock.data.ended = true;
  c.tick(at(500));
  assert.equal(c.phase, "disintegrating");
});

test("public replay becomes available only after the live window and plays independently from zero", (t) => {
  const at = browser(t);
  const c = controller();
  at(119999);
  c.replay();
  assert.equal(c.phase, "idle");
  at(140000);
  c.replay();
  assert.equal(c.phase, "countdown");
  assert.equal(c.mode, "replay");
  assert.equal(
    c.videoTarget.controls,
    false,
    "native controls remain hidden throughout playback",
  );
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  assert.equal(c.phase, "disintegrating");
  assert.equal(c.events[0].detail.durationMs, 8000);
  c.showVideo();
  assert.equal(c.videoTarget.controls, false);
  assert.equal(c.videoTarget.currentTime, 0);
  c.videoTarget.currentTime = 40;
  c.tick(at(500000));
  assert.equal(
    c.videoTarget.currentTime,
    40,
    "replay stays independent of the shared live timeline",
  );
  c.videoEnded();
  assert.equal(c.phase, "idle");
  assert.equal(c.events.at(-1).name, "reset");
});

test("replay shows twelve seconds, waits for zero, and restores the shared clocks on exit", (t) => {
  const at = browser(t);
  const values = ["", ""];
  document.querySelectorAll = () =>
    values.map((_, i) => ({
      getAttribute: () => values[i],
      setAttribute: (_, value) => {
        values[i] = value;
      },
    }));
  const c = controller();
  at(140000);
  c.replay();
  assert.deepEqual(
    values,
    Array(2).fill(new Date(start + 152000).toISOString()),
  );
  performance.now.mock.mockImplementation(() => 12999);
  c.tick();
  assert.equal(c.phase, "countdown");
  assert.equal(c.videoTarget.playCalls, 0);
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  assert.equal(c.phase, "disintegrating");
  assert.equal(c.videoTarget.currentTime, 0);
  c.finish();
  assert.deepEqual(values, ["", ""]);
  assert.equal(serverClock.data.ends_at, new Date(start).toISOString());
});

test("on-demand permits a private production replay before the deadline without starting the live finale early", (t) => {
  const at = browser(t);
  const c = controller();
  at(-3600000);
  c.replay();
  assert.equal(c.phase, "idle");
  serverClock.data.finale.on_demand = true;
  c.tick();
  assert.equal(
    c.phase,
    "idle",
    "enabling the flag never automatically plays it",
  );
  assert.equal(c.videoTarget.hasAttribute("src"), false);
  c.replay();
  assert.equal(c.phase, "countdown");
  assert.equal(c.mode, "replay");
  assert.equal(
    c.previewEnabledValue,
    false,
    "does not require local debug tools",
  );
  assert.equal(c.timeline.startsAt, start);
  serverClock.data.finale.on_demand = false;
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  assert.equal(
    c.phase,
    "disintegrating",
    "revocation doesn't interrupt an existing replay",
  );
  c.finish();
  assert.equal(c.skipLive, undefined);
  c.replay();
  assert.equal(c.phase, "idle", "revocation blocks new early playback");
  c.tick(at(0));
  assert.equal(c.mode, "live", "reviewing does not suppress the real event");
});

test("on-demand still requires a configured video and valid server time", (t) => {
  const at = browser(t);
  const c = controller();
  serverClock.data.finale.on_demand = true;
  serverClock.now.mock.mockImplementation(() => NaN);
  c.replay();
  assert.equal(c.phase, "idle");
  at(-60000);
  serverClock.data.finale.video_url = null;
  c.replay();
  assert.equal(c.phase, "idle");
});

test("local preview keeps the existing override and cannot be invoked in production", async (t) => {
  const at = browser(t);
  const c = controller();
  await c.preview();
  assert.equal(c.phase, "idle");
  c.previewEnabledValue = true;
  at(-60000);
  let value = "";
  document.querySelectorAll = () => [
    {
      getAttribute: () => value,
      setAttribute: (_, v) => {
        value = v;
      },
    },
  ];
  await c.preview();
  assert.equal(c.mode, "preview");
  assert.equal(value, new Date(start - 57000).toISOString());
  c.beginDisintegration();
  assert.deepEqual(
    c.events.at(-1).detail,
    {},
    "preview lets the renderer use its configured duration",
  );
  c.resetPreview();
  assert.equal(value, "");
  assert.equal(c.phase, "idle");
});

test("replay fades for two seconds and cancelled fades never show a video", async (t) => {
  browser(t);
  for (const cancel of [false, true]) {
    const c = controller();
    c.start("replay", finaleTimeline(sample()));
    c.beginDisintegration();
    const fading = c.beginFade(2000);
    assert.equal(c.fadeTarget.options.duration, 2000);
    if (cancel) c.cleanup();
    else c.fadeTarget.resolve();
    await fading;
    assert.equal(c.phase, cancel ? "idle" : "video");
  }
});

test("autoplay falls back to muted video and offers sound without restarting", async (t) => {
  const at = browser(t);
  const c = controller();
  c.videoTarget.play = async function () {
    if (!this.muted) throw new DOMException("blocked", "NotAllowedError");
    this.paused = false;
  };
  c.tick(at(40000));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(c.videoTarget.muted, true);
  assert.equal(c.playTarget.hidden, false);
  assert.equal(c.playTarget.textContent, "turn sound on");
  c.videoTarget.play = async function () {
    this.paused = false;
  };
  at(50000);
  c.playVideo();
  assert.equal(c.videoTarget.currentTime, 50);
  assert.equal(c.videoTarget.muted, false);
});

test("fully blocked autoplay is retryable and live completion still releases the page", async (t) => {
  const at = browser(t);
  const c = controller();
  c.videoTarget.play = async () => {
    throw new DOMException("blocked", "NotAllowedError");
  };
  c.tick(at(40000));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(c.playTarget.textContent, "play finale");
  assert.equal(c.playTarget.hidden, false);
  assert.equal(c.playBlocked, true);
  c.tick(at(120000));
  assert.equal(c.phase, "idle");
});

test("skipping a live video does not immediately reopen it or write account state", (t) => {
  const at = browser(t);
  const c = controller();
  t.mock.method(globalThis, "fetch", () => assert.fail("no dismissal request"));
  c.tick(at(40000));
  c.finish();
  c.tick(at(50000));
  assert.equal(c.phase, "idle");
  assert.equal(c.skipLive, true);
});

test("missing video configuration always restores the site instead of a permanent black screen", (t) => {
  const at = browser(t);
  serverClock.data.finale.video_url = null;
  const c = controller();
  c.tick(at(0));
  assert.equal(c.phase, "disintegrating");
  c.tick(at(10000));
  assert.equal(c.phase, "idle");
  assert.equal(c.videoTarget.hasAttribute("src"), false);
  c.replay();
  assert.equal(c.phase, "idle");
});

test("navigation aborts media and prevents a pending autoplay promise from reopening controls", async (t) => {
  const at = browser(t);
  const c = controller();
  let reject;
  c.videoTarget.play = () =>
    new Promise((_, fail) => {
      reject = fail;
    });
  c.tick(at(40000));
  c.cleanup({ restore: false });
  reject(new Error("navigation"));
  await Promise.resolve();
  assert.equal(c.phase, "idle");
  assert.equal(c.playTarget.hidden, true);
  assert.equal(c.videoTarget.hasAttribute("src"), false);
  assert.ok(!c.events.some((e) => e.name === "reset"));
});

test("timeline uses a finite runtime and never creates an infinite broadcast", () => {
  for (const duration of [undefined, -1, 0, NaN, Infinity]) {
    const data = sample();
    data.finale.duration_seconds = duration;
    assert.equal(finaleTimeline(data).finishesAt, start + 10000);
    assert.equal(finaleTimeline(data).ready, false);
  }
  assert.equal(finaleTimeline({}), null);
});

function interaction(overrides = {}) {
  return {
    isTrusted: true,
    type: "click",
    preventDefault() {},
    stopImmediatePropagation() {},
    ...overrides,
  };
}

test("first interaction offers guests one full replay, including after navigation", (t) => {
  const at = browser(t);
  const c = controller();
  at(140000);
  c.playOnArrival(interaction());
  assert.equal(c.mode, "replay");
  assert.equal(c.localDeadline, 13000);
  assert.equal(c.arrivalSeenValue, true);
  c.finish();
  c.playOnArrival(interaction());
  assert.equal(c.phase, "idle");
  const nextPage = controller();
  nextPage.playOnArrival(interaction());
  assert.equal(nextPage.phase, "idle");
  nextPage.replay();
  assert.equal(nextPage.mode, "replay", "manual replay remains available");
});

test("arrival requires real interaction, finished live show, ready media, and no other modal", (t) => {
  const at = browser(t);
  const c = controller();
  serverClock.data.finale.on_demand = true;
  at(-1000);
  c.playOnArrival(interaction());
  assert.equal(c.phase, "idle");
  at(140000);
  for (const options of [
    { isTrusted: false },
    { type: "keydown", key: "a" },
    { ctrlKey: true },
  ]) {
    c.playOnArrival(interaction(options));
    assert.equal(c.phase, "idle");
  }
  document.querySelector = () => ({});
  c.playOnArrival(interaction());
  assert.equal(c.phase, "idle");
  document.querySelector = () => null;
  serverClock.data.finale.video_url = null;
  c.playOnArrival(interaction());
  assert.equal(c.phase, "idle");
  serverClock.data.finale.video_url = "/videos/finale.mp4";
  c.playOnArrival(interaction({ type: "keydown", key: "Enter" }));
  assert.equal(c.mode, "replay");
});

test("signed-in arrival is recorded on the account and seen accounts do not repeat it", async (t) => {
  const at = browser(t);
  at(140000);
  const requests = [];
  t.mock.method(globalThis, "fetch", async (...args) => {
    requests.push(args);
    return { ok: true };
  });
  const seen = controller({ viewerIdValue: "1", arrivalSeenValue: true });
  seen.playOnArrival(interaction());
  assert.equal(seen.phase, "idle");
  assert.equal(requests.length, 0);
  const c = controller({ viewerIdValue: "2" });
  c.playOnArrival(interaction());
  assert.equal(requests.length, 1);
  assert.equal(requests[0][0], "/my/dismissals");
  assert.deepEqual(JSON.parse(requests[0][1].body), {
    thing_name: "stardance_finale_arrival_v1",
  });
  assert.equal(requests[0][1].credentials, "same-origin");
});

test("pages without a home clock show the countdown and storage failures do not break playback", (t) => {
  const at = browser(t);
  at(140000);
  t.mock.method(localStorage, "getItem", () => {
    throw new Error("blocked");
  });
  t.mock.method(localStorage, "setItem", () => {
    throw new Error("blocked");
  });
  const c = controller({
    hasCountdownTarget: true,
    countdownTarget: { hidden: true },
  });
  c.playOnArrival(interaction());
  assert.equal(c.dialogTarget.open, true);
  assert.equal(c.countdownTarget.hidden, false);
  assert.equal(c.countdownTarget.textContent, "stardance explodes in 12");
  performance.now.mock.mockImplementation(() => 13000);
  c.tick();
  assert.equal(c.countdownTarget.hidden, true);
  assert.equal(c.phase, "disintegrating");
  c.finish();
  assert.equal(c.dialogTarget.open, false);
});

test("escape exits playback and restores the site without a return button", (t) => {
  const at = browser(t);
  at(140000);
  const c = controller();
  c.replay();
  c.showVideo();
  let prevented = false;
  c.preventClose({
    preventDefault() {
      prevented = true;
    },
  });
  assert.equal(prevented, true);
  assert.equal(c.phase, "idle");
  assert.equal(c.dialogTarget.open, false);
  assert.equal(c.videoTarget.hasAttribute("src"), false);
});
