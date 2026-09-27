import test from "node:test";
import assert from "node:assert/strict";
import PhantomController from "../../app/javascript/controllers/phantom_void_controller.js";

const methods = PhantomController.prototype;
const qualityState = () => ({
  pixelSize: 2,
  qualityElapsed: 0,
  qualityFrames: 0,
  healthyTime: 0,
});

test("rendering processes every animation frame across common display refresh rates", () => {
  const originalRaf = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = () => 1;
  try {
    for (const refreshRate of [60, 120, 144]) {
      let draws = 0;
      const controller = {
        ...qualityState(),
        running: true,
        gl: {},
        time: 0,
        mouseStrength: 0,
        mouseVel: { x: 0, y: 0 },
        clicks: [],
        adaptQuality: methods.adaptQuality,
        draw: () => draws++,
      };
      for (let frame = 0; frame < refreshRate * 2; frame++)
        methods.tick.call(controller, (frame * 1000) / refreshRate);
      assert.equal(
        draws,
        refreshRate * 2,
        `${refreshRate}Hz must not skip frames`,
      );
      assert.equal(controller.pixelSize, 2);
      assert.ok(controller.time > 1.9 && controller.time < 2.01);
    }
  } finally {
    if (originalRaf === undefined) delete globalThis.requestAnimationFrame;
    else globalThis.requestAnimationFrame = originalRaf;
  }
});

test("quality adapts to sustained slow frames, recovers gradually, and stays bounded", () => {
  const controller = qualityState();
  methods.adaptQuality.call(controller, 100);
  assert.equal(controller.pixelSize, 2, "one hitch must not lower quality");
  for (let i = 0; i < 100; i++) methods.adaptQuality.call(controller, 60);
  assert.equal(controller.pixelSize, 4);
  assert.equal(controller.layoutDirty, true);
  controller.qualityElapsed = controller.qualityFrames = 0;
  for (let i = 0; i < 60; i++) methods.adaptQuality.call(controller, 34);
  assert.equal(controller.pixelSize, 4, "a short recovery must not oscillate");
  for (let i = 0; i < 180; i++) methods.adaptQuality.call(controller, 34);
  assert.equal(controller.pixelSize, 3);
  for (let i = 0; i < 600; i++) methods.adaptQuality.call(controller, 34);
  assert.equal(controller.pixelSize, 2);
});

test("layout reads are cached between frames and refreshed after a resize", () => {
  const originalStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = () => ({ borderTopLeftRadius: "20px" });
  let reads = 0;
  let viewportChanges = 0;
  const rect = { left: 100, top: 40, bottom: 520, width: 320, height: 480 };
  const target = (bounds) => ({
    getBoundingClientRect() {
      reads++;
      return bounds;
    },
  });
  const controller = {
    layoutDirty: true,
    pixelSize: 2,
    canvasTarget: { ...target(rect), width: 0, height: 0 },
    horizonTarget: target({ left: 120, top: 60, width: 280, height: 220 }),
    copyTarget: target({ left: 120, bottom: 500, width: 280, height: 200 }),
    gl: { viewport: () => viewportChanges++ },
    element: {},
  };
  try {
    assert.equal(methods.updateLayout.call(controller), true);
    assert.deepEqual(controller.layout.center, { x: 160, y: 350 });
    for (let i = 0; i < 60; i++) methods.updateLayout.call(controller);
    assert.equal(reads, 3, "no per-frame DOM measurement");
    assert.equal(viewportChanges, 1);
    controller.pixelSize = 4;
    controller.layoutDirty = true;
    methods.updateLayout.call(controller);
    assert.equal(controller.canvasTarget.width, 80);
    assert.equal(controller.canvasTarget.height, 120);
    assert.equal(controller.layout.scaleX, 0.25);
    assert.equal(reads, 6);
    rect.width = 400;
    controller.layoutDirty = true;
    methods.updateLayout.call(controller);
    assert.equal(controller.canvasTarget.width, 100);
    assert.equal(reads, 9);
  } finally {
    if (originalStyle === undefined) delete globalThis.getComputedStyle;
    else globalThis.getComputedStyle = originalStyle;
  }
});

test("pointer mapping follows scrolling and is independent of buffer resolution", () => {
  const rect = { left: 100, bottom: 500 };
  const controller = { canvasTarget: { getBoundingClientRect: () => rect } };
  assert.deepEqual(methods.pointerPosition.call(controller, 150, 400), {
    x: 50,
    y: 100,
  });
  rect.bottom -= 200;
  assert.deepEqual(methods.pointerPosition.call(controller, 150, 200), {
    x: 50,
    y: 100,
  });
});

test("shader arrays are reused and existing clicks scale with adaptive resolution", () => {
  const sent = new Map();
  const controller = {
    gl: new Proxy(
      {},
      {
        get:
          (_, name) =>
          (...args) =>
            sent.set(name, args),
      },
    ),
    uniforms: {},
    updateLayout: () => true,
    layout: { scaleX: 0.5, scaleY: 0.5, center: { x: 0, y: 0 }, guard: {} },
    mouse: { x: 40, y: 80 },
    mouseVel: { x: 0, y: 0 },
    clicks: [{ x: 40, y: 80, age: 1 }],
    clickAges: new Float32Array(6),
    clickPositions: new Float32Array(12),
  };
  methods.draw.call(controller);
  assert.equal(sent.get("uniform1fv")[1], controller.clickAges);
  assert.equal(sent.get("uniform2fv")[1], controller.clickPositions);
  assert.deepEqual([...controller.clickPositions.slice(0, 2)], [20, 40]);
  controller.layout.scaleX = controller.layout.scaleY = 0.25;
  methods.draw.call(controller);
  assert.equal(sent.get("uniform2fv")[1], controller.clickPositions);
  assert.deepEqual([...controller.clickPositions.slice(0, 2)], [10, 20]);
  assert.deepEqual(controller.clicks[0], { x: 40, y: 80, age: 1 });
});

test("hidden and offscreen ads stop rendering; resume resets cadence samples", () => {
  const originalDocument = globalThis.document;
  const originalRaf = globalThis.requestAnimationFrame;
  const originalCancel = globalThis.cancelAnimationFrame;
  let canceled = 0;
  globalThis.document = { hidden: false };
  globalThis.requestAnimationFrame = () => 1;
  globalThis.cancelAnimationFrame = () => canceled++;
  const controller = { interactive: true, visible: true, qualityElapsed: 1000 };
  try {
    methods.syncLoop.call(controller);
    assert.equal(controller.running, true);
    assert.equal(controller.qualityElapsed, 0);
    document.hidden = true;
    methods.syncLoop.call(controller);
    assert.equal(controller.running, false);
    assert.equal(canceled, 1);
    document.hidden = false;
    controller.visible = false;
    methods.syncLoop.call(controller);
    assert.equal(controller.running, false);
    controller.visible = true;
    controller.interactive = false;
    methods.syncLoop.call(controller);
    assert.equal(controller.running, false, "reduced motion stays static");
  } finally {
    for (const [key, value] of Object.entries({
      document: originalDocument,
      requestAnimationFrame: originalRaf,
      cancelAnimationFrame: originalCancel,
    })) {
      if (value === undefined) delete globalThis[key];
      else globalThis[key] = value;
    }
  }
});

test("pointer speed ignores high polling rates and coarse timestamps", () => {
  const rect = { left: 0, bottom: 200 };
  const pointerState = () => ({
    interactive: true,
    layout: { height: 200 },
    mouseVel: { x: 0, y: 0 },
    lastMove: null,
    canvasTarget: { getBoundingClientRect: () => rect },
    pointerPosition: methods.pointerPosition,
  });
  const move = (controller, clientX, timeStamp) =>
    methods.track.call(controller, { clientX, clientY: 100, timeStamp });

  const firefox = pointerState();
  for (let i = 0; i < 200; i++) move(firefox, 100 + (i % 2), Math.floor(i / 4));
  assert.ok(
    Math.hypot(firefox.mouseVel.x, firefox.mouseVel.y) < 0.5,
    "1px jitter at 1000Hz with repeated timestamps must not read as a flick",
  );
  assert.deepEqual(firefox.mouse, { x: 101, y: 100 });

  const flick = pointerState();
  move(flick, 0, 0);
  move(flick, 5000, 20);
  assert.ok(Math.hypot(flick.mouseVel.x, flick.mouseVel.y) <= 3);

  const steady = pointerState();
  for (let i = 0; i <= 30; i++) move(steady, i * 4, i * (1000 / 60));
  assert.ok(Math.abs(steady.mouseVel.x - 1.2) < 0.01);
  assert.equal(steady.mouseVel.y, 0);
});
