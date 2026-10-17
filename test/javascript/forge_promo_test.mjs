import test from "node:test";
import assert from "node:assert/strict";
import ForgePromoController from "../../app/javascript/controllers/forge_promo_controller.js";

function click(overrides = {}) {
  return {
    button: 0,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    ...overrides,
  };
}

function setup(t, { wave = {} } = {}) {
  const requests = [];
  const navigations = [];
  t.mock.method(globalThis, "fetch", (...args) => {
    requests.push(args);
    return Promise.resolve();
  });
  const previousWindow = globalThis.window;
  globalThis.window = { location: { assign: (url) => navigations.push(url) } };
  t.after(() => {
    if (previousWindow === undefined) delete globalThis.window;
    else globalThis.window = previousWindow;
  });
  const animation = {};
  animation.promise = new Promise((resolve) => {
    animation.resolve = resolve;
  });
  const controller = {
    cardTarget: { href: "https://stardance.test/promos/forge" },
    urlValue:
      "https://forge.hackclub.com/?utm_source=stardance&utm_medium=discover_rail",
    buildWave: () => wave,
    sweep: () => animation.promise,
  };
  const ignite = (event) =>
    ForgePromoController.prototype.ignite.call(controller, event);
  return { requests, navigations, controller, animation, ignite };
}

test("tracks immediately with keepalive, suppresses repeated clicks, and navigates without recounting", async (t) => {
  const { requests, navigations, controller, animation, ignite } = setup(t);
  const first = click();
  const pending = ignite(first);
  assert.equal(first.defaultPrevented, true);
  assert.equal(requests.length, 1);
  assert.deepEqual(requests[0], [
    controller.cardTarget.href,
    {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      cache: "no-store",
      keepalive: true,
    },
  ]);
  assert.deepEqual(navigations, []);

  await ignite(click());
  assert.equal(requests.length, 1);

  animation.resolve();
  await pending;
  assert.deepEqual(navigations, [controller.urlValue]);
  assert.equal(requests.length, 1);
});

test("modified, reduced-motion, and no-WebGL clicks use only the native tracked link", async (t) => {
  const { requests, navigations, controller, ignite } = setup(t);
  for (const modifiers of [
    { button: 1 },
    { metaKey: true },
    { ctrlKey: true },
    { shiftKey: true },
    { altKey: true },
  ]) {
    const event = click(modifiers);
    await ignite(event);
    assert.equal(event.defaultPrevented, false);
  }

  controller.reduceMotion = true;
  const reduced = click();
  await ignite(reduced);
  assert.equal(reduced.defaultPrevented, false);

  controller.reduceMotion = false;
  controller.buildWave = () => null;
  const noWebgl = click();
  await ignite(noWebgl);
  assert.equal(noWebgl.defaultPrevented, false);

  assert.deepEqual(requests, []);
  assert.deepEqual(navigations, []);
});

test("a lost tracking response never retries or sends navigation through tracking again", async (t) => {
  const { requests, navigations, controller, animation, ignite } = setup(t);
  globalThis.fetch.mock.mockImplementation((...args) => {
    requests.push(args);
    return Promise.reject(new TypeError("Network error"));
  });
  const pending = ignite(click());
  animation.resolve();
  await pending;
  assert.equal(requests.length, 1);
  assert.deepEqual(navigations, [controller.urlValue]);
});

test("the burnt edge is re-cut on a steady cadence while sparks still move every frame", (t) => {
  const previousRaf = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = () => 1;
  t.after(() => {
    if (previousRaf === undefined) delete globalThis.requestAnimationFrame;
    else globalThis.requestAnimationFrame = previousRaf;
  });
  const burns = [];
  let sparkSteps = 0;
  const controller = {
    running: true,
    lastTick: null,
    time: 0,
    heat: 1,
    targetHeat: 1,
    burn(dt) {
      burns.push([this.time, dt]);
    },
    kindle() {},
    sparks: {
      step() {
        sparkSteps++;
      },
      draw() {},
    },
  };
  const tick = (now) =>
    ForgePromoController.prototype.tick.call(controller, now);

  for (const now of [1000, 1016, 1033, 1050, 1066, 1083, 1100]) tick(now);

  assert.equal(sparkSteps, 7);
  assert.deepEqual(
    burns.map(([, dt]) => dt),
    [0, 0, 0],
  );
  // The outline's clock keeps running between cuts, so it creeps at the same speed as before.
  assert.ok(Math.abs(controller.time - 0.1) < 1e-9);
  assert.ok(Math.abs(burns[1][0] - 0.05) < 1e-9);
});
