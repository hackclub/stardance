import test from "node:test";
import assert from "node:assert/strict";
import { serverClock } from "../../app/javascript/lib/server_clock.js";
import FinaleController from "../../app/javascript/controllers/stardance_finale_controller.js";

function controller(overrides = {}) {
  const state = {
    phase: "idle",
    endsAtValue: "2026-11-01T04:00:00Z",
    seenValue: false,
    previewEnabledValue: false,
    viewerIdValue: "1",
    storageKey: "stardance_finale:1",
    dialogTarget: { showModal() {}, close() {} },
    panelTarget: {},
    hasStatusTarget: true,
    hasContinueTarget: true,
    statusTarget: {},
    previewResetTarget: {},
    continueTarget: { focus() {} },
    dispatch(name) {
      this.events.push(name);
    },
    events: [],
    alreadySeen: () => false,
    finish() {},
    confirmFinale() {
      this.beginDisintegration();
    },
    ...overrides,
  };
  for (const name of ["start", "cleanup", "tick", "beginDisintegration"])
    state[name] = FinaleController.prototype[name].bind(state);
  return state;
}

function browser(t, overrides = {}) {
  const anchor = serverClock.anchor;
  serverClock.anchor = {
    server: Date.parse("2026-10-26T12:00:00Z"),
    local: performance.now(),
  };
  t.after(() => {
    serverClock.anchor = anchor;
  });
  for (const [name, value] of Object.entries({
    document: {
      hidden: false,
      querySelector: () => null,
      querySelectorAll: () => [],
    },
    ...overrides,
  })) {
    const original = globalThis[name];
    globalThis[name] = value;
    t.after(() => {
      globalThis[name] = original;
    });
  }
}

test("deadline gates the finale, and even days-late arrivals see the full red countdown", (t) => {
  browser(t);
  const c = controller();
  const end = Date.parse(c.endsAtValue);
  c.tick(end - 3001);
  assert.equal(c.phase, "idle");
  c.tick(end + 86400000);
  assert.equal(c.phase, "countdown");
  assert.equal(c.countdownEndsAt, end + 86403000);
  c.tick(end + 86401000);
  assert.equal(c.phase, "countdown");
  c.tick(end + 86402000);
  assert.equal(c.phase, "countdown");
  c.tick(end + 86403000);
  assert.equal(c.phase, "disintegrating");
  assert.deepEqual(c.events, ["disintegrate"]);
  assert.equal(c.panelTarget.hidden, true);
  FinaleController.prototype.showVideo.call(c);
  assert.equal(c.phase, "video");
  assert.equal(c.panelTarget.hidden, false);
});

test("seen viewers, invalid deadlines, active stories and background tabs do not start", (t) => {
  browser(t);
  for (const overrides of [{ alreadySeen: () => true }, { endsAtValue: "" }]) {
    const c = controller(overrides);
    c.tick(Date.parse("2026-11-05"));
    assert.equal(c.phase, "idle");
  }
  for (const doc of [
    { hidden: true },
    { hidden: false, querySelector: () => ({}) },
  ]) {
    globalThis.document = doc;
    const c = controller();
    c.tick(Date.parse("2026-11-05"));
    assert.equal(c.phase, "idle");
  }
});

test("video cannot start before destruction completes", () => {
  const c = controller({ phase: "countdown", panelTarget: { hidden: true } });
  FinaleController.prototype.showVideo.call(c);
  assert.equal(c.panelTarget.hidden, true);
});

test("local replay works for seen users and never records completion", async (t) => {
  browser(t, { fetch: () => assert.fail("preview must never save") });
  const c = controller({ previewEnabledValue: true, seenValue: true });
  await FinaleController.prototype.preview.call(c);
  assert.equal(c.phase, "countdown");
  assert.equal(c.previewing, true);
  c.phase = "video";
  await FinaleController.prototype.finish.call(c);
  assert.equal(c.phase, "idle");
  assert.deepEqual(c.events, ["reset"]);
});

test("production cannot invoke local replay", async () => {
  const c = controller();
  await FinaleController.prototype.preview.call(c);
  assert.equal(c.phase, "idle");
});

test("completion saves once and suppresses replay on cached pages", async (t) => {
  let calls = 0;
  const saved = new Map();
  browser(t, {
    fetch: async (url, options) => {
      calls++;
      assert.equal(url, "/my/dismissals");
      assert.equal(JSON.parse(options.body).thing_name, "stardance_finale");
      return { ok: true };
    },
    localStorage: {
      setItem: (key, value) => saved.set(key, value),
      getItem: (key) => saved.get(key),
    },
  });
  const c = controller({ phase: "video", dismissUrlValue: "/my/dismissals" });
  await FinaleController.prototype.finish.call(c);
  await FinaleController.prototype.finish.call(c);
  assert.equal(calls, 1);
  assert.equal(c.seenValue, true);
  assert.equal(FinaleController.prototype.alreadySeen.call(controller()), true);
  assert.equal(
    FinaleController.prototype.alreadySeen.call(
      controller({ storageKey: "stardance_finale:2" }),
    ),
    false,
  );
});

test("failed completion stays retryable and does not mark the account seen", async (t) => {
  browser(t, { fetch: async () => ({ ok: false }) });
  const c = controller({ phase: "video" });
  await FinaleController.prototype.finish.call(c);
  assert.equal(c.phase, "video");
  assert.equal(c.seenValue, false);
  assert.equal(c.continueTarget.disabled, false);
  assert.match(c.statusTarget.textContent, /try continue again/);
});

test("blocked autoplay exposes a play button", async () => {
  const c = controller({
    phase: "video",
    playTarget: { focus() {} },
    videoTarget: {
      play: async () => {
        throw new Error("blocked");
      },
    },
  });
  await FinaleController.prototype.playVideo.call(c);
  assert.equal(c.playTarget.hidden, false);
  assert.match(c.statusTarget.textContent, /Press play/);
});

test("navigation cleanup does not reapply damage to a Turbo snapshot", () => {
  const c = controller({ phase: "video" });
  c.cleanup({ restore: false });
  assert.equal(c.phase, "idle");
  assert.deepEqual(c.events, []);
});

test("live clock starts its final three seconds without adding another countdown at zero", (t) => {
  browser(t);
  const c = controller();
  const deadline = Date.parse(c.endsAtValue);
  c.tick(deadline - 3000);
  assert.equal(c.countdownEndsAt, deadline);
  c.tick(deadline);
  assert.deepEqual(c.events, ["disintegrate"]);
});

test("preview updates the existing clock and restores its real deadline on reset", (t) => {
  let deadline = "2026-11-01T04:00:00Z";
  const original = deadline;
  const clock = {
    getAttribute: () => deadline,
    setAttribute(name, value) {
      deadline = value;
    },
  };
  browser(t, { document: { hidden: false, querySelectorAll: () => [clock] } });
  const c = controller();
  c.start(1000, true);
  assert.equal(deadline, new Date(4000).toISOString());
  c.cleanup();
  assert.equal(deadline, original);
});

test("the finale waits for server confirmation even if estimated time is past zero", async (t) => {
  browser(t);
  const c = controller({ phase: "countdown" });
  t.mock.method(serverClock, "sync", async () => ({ ended: false }));
  await FinaleController.prototype.confirmFinale.call(c);
  assert.equal(c.phase, "countdown");
  assert.deepEqual(c.events, []);
  c.nextEndCheck = 0;
  serverClock.sync.mock.mockImplementation(async () => ({ ended: true }));
  await FinaleController.prototype.confirmFinale.call(c);
  assert.equal(c.phase, "disintegrating");
});

test("an offline server confirmation never starts destruction", async (t) => {
  browser(t);
  const c = controller({ phase: "countdown" });
  t.mock.method(serverClock, "sync", async () => null);
  await FinaleController.prototype.confirmFinale.call(c);
  assert.deepEqual(c.events, []);
});

test("blank placeholder hides preview controls and saves completion without restoring the site", async (t) => {
  browser(t, {
    fetch: async () => ({ ok: true }),
    localStorage: { setItem() {} },
  });
  const c = controller({
    phase: "disintegrating",
    hasVideoTarget: false,
    hasStatusTarget: false,
    hasContinueTarget: false,
  });
  let completion;
  c.finish = (options) => {
    completion = FinaleController.prototype.finish.call(c, options);
  };
  FinaleController.prototype.showVideo.call(c);
  await completion;
  assert.equal(c.previewResetTarget.hidden, true);
  assert.equal(c.panelTarget.hidden, false);
  assert.equal(c.phase, "complete");
  assert.equal(c.seenValue, true);
  assert.deepEqual(c.events, []);
});
