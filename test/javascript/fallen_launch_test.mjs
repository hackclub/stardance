import test from "node:test";
import assert from "node:assert/strict";
import FallenLaunchController from "../../app/javascript/controllers/fallen_launch_controller.js";

const TRACKED_HREF = "https://stardance.test/promos/fallen";
const FALLEN_URL =
  "https://fallen.hackclub.com/?utm_source=stardance&utm_medium=discover_rail";

function click(overrides = {}) {
  return {
    button: 0,
    detail: 1,
    clientX: 40,
    clientY: 60,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    currentTarget: {
      href: TRACKED_HREF,
      getBoundingClientRect: () => ({
        left: 100,
        top: 200,
        width: 50,
        height: 80,
      }),
    },
    ...overrides,
  };
}

function setup(t, { reduceMotion = false } = {}) {
  const requests = [];
  const navigations = [];
  const appended = [];
  const listeners = {};
  t.mock.method(globalThis, "fetch", (...args) => {
    requests.push(args);
    return Promise.resolve();
  });
  t.mock.timers.enable({ apis: ["setTimeout"] });

  const previous = { window: globalThis.window, document: globalThis.document };
  globalThis.window = {
    location: { assign: (url) => navigations.push(url) },
    matchMedia: () => ({ matches: reduceMotion }),
    addEventListener: (name, handler) => (listeners[name] = handler),
    removeEventListener: (name) => delete listeners[name],
  };
  globalThis.document = { body: { append: (node) => appended.push(node) } };
  t.after(() => {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) delete globalThis[name];
      else globalThis[name] = value;
    }
  });

  const overlay = {
    removed: false,
    origin: {},
    style: { setProperty: (name, value) => (overlay.origin[name] = value) },
    remove: () => (overlay.removed = true),
  };
  const controller = Object.assign(
    Object.create(FallenLaunchController.prototype),
    {
      urlValue: FALLEN_URL,
      takeoverTarget: {
        content: { firstElementChild: { cloneNode: () => overlay } },
      },
    },
  );
  controller.connect();
  return { requests, navigations, appended, listeners, overlay, controller };
}

test("tracks at once, plays the send-off from the click, ignores repeats, then opens fallen directly", (t) => {
  const { requests, navigations, appended, overlay, controller } = setup(t);

  const first = click();
  controller.launch(first);
  assert.equal(first.defaultPrevented, true);
  assert.deepEqual(requests, [
    [
      TRACKED_HREF,
      {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        keepalive: true,
      },
    ],
  ]);
  assert.deepEqual(appended, [overlay]);
  assert.deepEqual(overlay.origin, { "--x": "40px", "--y": "60px" });

  const repeated = click();
  controller.launch(repeated);
  assert.equal(repeated.defaultPrevented, true);
  assert.equal(requests.length, 1);
  assert.equal(appended.length, 1);

  t.mock.timers.tick(1949);
  assert.deepEqual(navigations, []);
  t.mock.timers.tick(1);
  assert.deepEqual(navigations, [FALLEN_URL]);
  assert.equal(requests.length, 1);
});

test("a keyboard click sweeps from the middle of the card", (t) => {
  const { overlay, controller } = setup(t);
  controller.launch(click({ detail: 0 }));
  assert.deepEqual(overlay.origin, { "--x": "125px", "--y": "240px" });
});

test("modified clicks and reduced motion use only the native tracked link", async (t) => {
  for (const [overrides, reduceMotion] of [
    [{ button: 1 }, false],
    [{ metaKey: true }, false],
    [{ ctrlKey: true }, false],
    [{ shiftKey: true }, false],
    [{ altKey: true }, false],
    [{}, true],
  ]) {
    await t.test(JSON.stringify({ overrides, reduceMotion }), (t) => {
      const { requests, navigations, appended, controller } = setup(t, {
        reduceMotion,
      });
      const event = click(overrides);
      controller.launch(event);
      t.mock.timers.tick(5000);
      assert.equal(event.defaultPrevented, false);
      assert.deepEqual(requests, []);
      assert.deepEqual(appended, []);
      assert.deepEqual(navigations, []);
    });
  }
});

test("coming back with the back button clears the send-off", (t) => {
  const { navigations, listeners, overlay, controller } = setup(t);
  controller.launch(click());

  listeners.pageshow({ persisted: false });
  assert.equal(overlay.removed, false);

  listeners.pageshow({ persisted: true });
  assert.equal(overlay.removed, true);
  t.mock.timers.tick(5000);
  assert.deepEqual(navigations, []);
});

test("disconnecting mid-launch clears the send-off and cancels the navigation", (t) => {
  const { navigations, listeners, overlay, controller } = setup(t);
  controller.launch(click());

  controller.disconnect();
  assert.equal(overlay.removed, true);
  assert.equal(listeners.pageshow, undefined);
  t.mock.timers.tick(5000);
  assert.deepEqual(navigations, []);
});
