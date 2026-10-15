import test from "node:test";
import assert from "node:assert/strict";
import MipmapPromoController from "../../app/javascript/controllers/mipmap_promo_controller.js";

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

function setup(t) {
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
    cardTarget: { href: "https://stardance.test/promos/mipmap" },
    urlValue:
      "https://mipmap.hackclub.com/?utm_source=stardance&utm_medium=discover_rail",
    syncLoop() {},
    buildScene() {},
    shoot: () => animation.promise,
    async pull() {},
    async close() {},
  };
  const launch = (event) =>
    MipmapPromoController.prototype.launch.call(controller, event);
  return { requests, navigations, controller, animation, launch };
}

test("tracks immediately with keepalive, suppresses repeated clicks, and navigates without recounting", async (t) => {
  const { requests, navigations, controller, animation, launch } = setup(t);
  const first = click();
  const pending = launch(first);
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

  const repeated = click();
  await launch(repeated);
  assert.equal(repeated.defaultPrevented, true);
  assert.equal(requests.length, 1);

  animation.resolve();
  await pending;
  assert.deepEqual(navigations, [controller.urlValue]);
  assert.equal(requests.length, 1);
});

test("modified and reduced-motion clicks use only the native tracked link", async (t) => {
  const { requests, navigations, controller, launch } = setup(t);
  for (const launching of [false, true]) {
    controller.launching = launching;
    for (const modifiers of [
      { button: 1 },
      { metaKey: true },
      { ctrlKey: true },
      { shiftKey: true },
      { altKey: true },
    ]) {
      const event = click(modifiers);
      await launch(event);
      assert.equal(event.defaultPrevented, false);
    }
  }
  controller.launching = false;
  controller.reduceMotion = true;
  const event = click();
  await launch(event);
  assert.equal(event.defaultPrevented, false);
  assert.deepEqual(requests, []);
  assert.deepEqual(navigations, []);
});

test("a lost tracking response never retries or sends navigation through tracking again", async (t) => {
  const { requests, navigations, controller, animation, launch } = setup(t);
  globalThis.fetch.mock.mockImplementation((...args) => {
    requests.push(args);
    return Promise.reject(new TypeError("Network error"));
  });
  const pending = launch(click());
  animation.resolve();
  await pending;
  assert.equal(requests.length, 1);
  assert.deepEqual(navigations, [controller.urlValue]);
});
